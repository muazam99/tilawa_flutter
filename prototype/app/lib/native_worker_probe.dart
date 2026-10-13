// Private experiment: all synchronous JS work stays off Flutter's UI isolate.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
import 'native_probe_adapter.dart';

final class NativeWorkerProbeFactory implements TilawaEngineAdapterFactory {
  const NativeWorkerProbeFactory();
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async {
    final token = ServicesBinding.rootIsolateToken;
    if (token == null) {
      throw StateError('Native worker must open from root Flutter isolate');
    }
    final adapter = _WorkerAdapter(sink);
    // Separate bootstrap lease survives a bounded caller wait until real cleanup.
    assets.retain();
    try {
      final script = await rootBundle.loadString(
        'assets/runtime/native_probe.js',
      );
      adapter.isolate = await Isolate.spawn(
        _workerEntry,
        [
          adapter.port.sendPort,
          token,
          assets.files.map((name, file) => MapEntry(name, file.path)),
          config,
          script,
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
  String get id => 'private-native-ort-quickjs-worker';
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
  final core = NativeProbeAdapter(
    (event) => root.send({'kind': 'event', 'event': event}),
  );
  final commands = ReceivePort();
  root.send({'kind': 'commands', 'commands': commands.sendPort});
  Object? startupFailure;
  Future<void> queue = () async {
    try {
      await core.initializeFiles(
        (args[2] as Map<String, String>).map(
          (name, path) => MapEntry(name, File(path)),
        ),
        args[3] as TilawaRecognitionConfig,
        args[4] as String,
      );
      root.send({'kind': 'ready'});
    } catch (error) {
      startupFailure = error;
      root.send({'kind': 'startup-error', 'error': '$error'});
    }
  }();
  commands.listen((dynamic request) {
    final message = request as Map;
    queue = queue.then((_) async {
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
