import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

import '../adapter.dart';
import '../assets.dart';
import '../models.dart';
import 'native_core.dart';

final class TilawaNativeAdapterFactory implements TilawaEngineAdapterFactory {
  const TilawaNativeAdapterFactory({
    this.intraOpNumThreads = 1,
    this.useArena = false,
  });
  // Internal experimental controls. The development default stays measured.
  final int intraOpNumThreads;
  final bool useArena;
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async {
    if (!Platform.isAndroid) {
      throw const TilawaException(
        'unsupportedPlatform',
        'Native adapter requires Android.',
      );
    }
    final manifest = assets.manifest;
    final pinned = TilawaAssetManifest.zipformerV1();
    if (manifest.engineId != 'zipformer' ||
        manifest.upstreamCommit != tilawaUpstreamCommit ||
        manifest.segmentationId != tilawaSegmentationId ||
        manifest.corpusSha256 != tilawaCorpusSha256 ||
        manifest.ioSchema != 'zipformer-a0w-ep1-a05' ||
        manifest.file('model.onnx').sha256 !=
            pinned.file('model.onnx').sha256 ||
        manifest.file('io.json').sha256 != pinned.file('io.json').sha256) {
      throw const TilawaException(
        'incompatibleAssets',
        'Native adapter requires the pinned Zipformer baseline.',
      );
    }
    final version = await const MethodChannel(
      'dev.tilawa/runtime',
    ).invokeMethod<String>('version');
    if (version != '1.24.2') {
      throw TilawaException(
        'incompatibleAssets',
        'Native ONNX runtime version mismatch: $version.',
      );
    }
    final token = ServicesBinding.rootIsolateToken;
    if (token == null) {
      throw StateError('Native worker must open from root Flutter isolate');
    }
    final adapter = _WorkerAdapter(sink);
    // Separate bootstrap lease survives a bounded caller wait until real cleanup.
    assets.retain();
    try {
      final runtime =
          jsonDecode(
                await rootBundle.loadString(
                  'packages/tilawa_flutter/assets/runtime/manifest.json',
                ),
              )
              as Map;
      if (runtime['upstreamCommit'] != tilawaUpstreamCommit ||
          runtime['ortVersion'] != version ||
          runtime['quickjsVersion'] != '0.1.6') {
        throw const TilawaException(
          'incompatibleAssets',
          'Bundled native runtime baseline mismatch.',
        );
      }
      final bytes = await rootBundle.load(
        'packages/tilawa_flutter/assets/runtime/native.js',
      );
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final artifact = (runtime['artifacts'] as List).cast<Map>().singleWhere(
        (a) => a['name'] == 'native.js',
      );
      if (data.length != artifact['bytes'] ||
          sha256.convert(data).toString() != artifact['sha256']) {
        throw const TilawaException(
          'assetIntegrityMismatch',
          'Bundled native bridge integrity mismatch.',
        );
      }
      final script = utf8.decode(data);
      adapter.isolate = await Isolate.spawn(
        _workerEntry,
        [
          adapter.port.sendPort,
          token,
          assets.files.map((name, file) => MapEntry(name, file.path)),
          config,
          script,
          intraOpNumThreads,
          useArena,
        ],
        onError: adapter.port.sendPort,
        onExit: adapter.port.sendPort,
        errorsAreFatal: true,
      );
      await adapter.ready.future.timeout(const Duration(seconds: 30));
      assets.release();
      return adapter;
    } catch (_) {
      final cleanup = adapter.dispose();
      unawaited(
        cleanup.then(
          (_) => assets.release(),
          onError: (Object _, StackTrace __) {},
        ),
      );
      await cleanup.timeout(config.disposalDeadline);
      rethrow;
    }
  }
}

final class _WorkerAdapter implements TilawaEngineAdapter {
  _WorkerAdapter(this.sink) {
    ready.future.ignore();
    port.listen(receive);
  }
  final TilawaObservationSink sink;
  final port = ReceivePort();
  final ready = Completer<void>();
  final pending = <int, Completer<Object?>>{};
  SendPort? commands;
  Isolate? isolate;
  int next = 0;
  bool closed = false, workerExited = false;
  Future<void>? disposal;
  @override
  String get id => 'native-ort-quickjs-worker';
  @override
  String get version => 'ort-1.24.2-quickjs-ng0140';
  @override
  TilawaCapabilities get capabilities => TilawaCapabilities(
    observations: {
      'verse_candidate',
      'verse_match',
      'word_progress',
      'raw_transcript',
      'final_sequence',
      'debug',
    },
  );
  void receive(dynamic message) {
    if (message == null || message is List) {
      workerExited = true;
      final error = TilawaException(
        'bridgeDisconnected',
        'Native worker exited: $message',
      );
      if (!ready.isCompleted) ready.completeError(error);
      for (final operation in pending.values) {
        operation.completeError(error);
      }
      pending.clear();
      if (!closed) sink({'type': '_runtime_failure', 'message': error.message});
      return;
    }
    final data = message as Map;
    if (data['kind'] == 'commands') {
      commands = data['commands'] as SendPort;
      // Native ownership starts only after the root has a cleanup command port.
      commands!.send({'method': 'initialize'});
    } else if (data['kind'] == 'ready') {
      if (!ready.isCompleted) ready.complete();
    } else if (data['kind'] == 'event') {
      if (!closed) sink(Map<String, Object?>.from(data['event'] as Map));
    } else if (data['kind'] == 'reply') {
      final completion = pending.remove(data['id']);
      if (completion != null) {
        if (data['error'] != null) {
          completion.completeError(
            TilawaException('inferenceFailed', '${data['error']}'),
          );
        } else {
          completion.complete(data['result']);
        }
      }
    } else if (data['kind'] == 'startup-error') {
      if (!ready.isCompleted) {
        ready.completeError(
          TilawaException('runtimeInitializationFailed', '${data['error']}'),
        );
      }
    }
  }

  Future<Object?> call(String method, [Object? data]) {
    if (commands == null || workerExited) {
      throw const TilawaException(
        'bridgeDisconnected',
        'Native worker unavailable',
      );
    }
    final id = ++next, operation = Completer<Object?>();
    pending[id] = operation;
    commands!.send({'id': id, 'method': method, 'data': data});
    return operation.future;
  }

  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async =>
      await call(
            'feed',
            TransferableTypedData.fromList([
              pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
            ]),
          )
          as TilawaEngineSnapshot;
  @override
  Future<TilawaEngineSnapshot> stop() async =>
      await call('stop') as TilawaEngineSnapshot;
  @override
  Future<TilawaEngineSnapshot> reset() async =>
      await call('reset') as TilawaEngineSnapshot;
  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async =>
      await call('wordCount', ayah) as int;
  @override
  Future<void> dispose() => disposal ??= () async {
    closed = true;
    if (commands == null) {
      isolate?.kill(priority: Isolate.immediate);
      port.close();
      return;
    }
    // Only end the isolate after native tensors/runtime acknowledge cleanup.
    // Unexpected worker loss must remain a disposal failure, preserving leases.
    await call('dispose');
    port.close();
    isolate?.kill(priority: Isolate.immediate);
  }();
}

Future<void> _workerEntry(List<Object?> args) async {
  final root = args[0] as SendPort;
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    args[1] as RootIsolateToken,
  );
  final core = NativeCoreAdapter(
    (event) => root.send({'kind': 'event', 'event': event}),
  );
  final commands = ReceivePort();
  root.send({'kind': 'commands', 'commands': commands.sendPort});
  Object? startupFailure;
  Future<void> queue = Future.value();
  commands.listen((dynamic request) {
    final message = request as Map;
    queue = queue.then((_) async {
      if (message['method'] == 'initialize') {
        try {
          await core.initializeFiles(
            (args[2] as Map<String, String>).map(
              (name, path) => MapEntry(name, File(path)),
            ),
            args[3] as TilawaRecognitionConfig,
            args[4] as String,
            intraOpNumThreads: args[5] as int,
            useArena: args[6] as bool,
          );
          root.send({'kind': 'ready'});
        } catch (error) {
          startupFailure = error;
          root.send({'kind': 'startup-error', 'error': '$error'});
        }
        return;
      }
      try {
        if (startupFailure != null && message['method'] != 'dispose') {
          throw StateError('Native initialization failed: $startupFailure');
        }
        Object? result;
        switch (message['method']) {
          case 'feed':
            final buffer = (message['data'] as TransferableTypedData)
                .materialize();
            result = await core.feed(Float32List.view(buffer));
          case 'stop':
            result = await core.stop();
          case 'reset':
            result = await core.reset();
          case 'wordCount':
            result = await core.describeAyah(message['data'] as TilawaAyahRef);
          case 'dispose':
            await core.dispose();
            commands.close();
          default:
            throw StateError('Unknown native worker operation');
        }
        root.send({'kind': 'reply', 'id': message['id'], 'result': result});
      } catch (error) {
        root.send({'kind': 'reply', 'id': message['id'], 'error': '$error'});
      }
    });
  });
}
