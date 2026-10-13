// Private candidate: native tensors/inference, browser JIT for pinned matching.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
// ignore: implementation_imports
import 'package:tilawa_flutter/src/runtime/native_core.dart';
// ignore: implementation_imports
import 'package:tilawa_flutter/src/assets.dart' show newTilawaId;

final class HybridProbeFactory implements TilawaEngineAdapterFactory {
  const HybridProbeFactory();
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async {
    final adapter = _Hybrid(sink);
    assets.retain();
    try {
      await adapter.initialize(assets, config);
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

final class _Messages {
  void Function(String)? receive;
}

final class _Hybrid implements TilawaEngineAdapter {
  _Hybrid(this.sink);
  final TilawaObservationSink sink;
  final router = _Messages();
  final ready = Completer<void>();
  final pending = <int, Completer<Map<String, Object?>>>{};
  _InferenceWorker? worker;
  WebViewController? controller;
  HttpServer? server;
  StreamSubscription<HttpRequest>? requests;
  int next = 0;
  bool closing = false;
  Future<void>? disposal;
  @override
  String get id => 'private-native-ort-browser';
  @override
  String get version => 'ort-1.24.2-browser-matching';
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
  Future<void> initialize(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
  ) async {
    ready.future.ignore();
    final version = await const MethodChannel(
      'dev.tilawa/runtime',
    ).invokeMethod<String>('version');
    if (version != '1.24.2') {
      throw StateError('Native runtime mismatch: $version');
    }
    final manifest =
        jsonDecode(
              await rootBundle.loadString(
                'packages/tilawa_flutter/assets/runtime/manifest.json',
              ),
            )
            as Map;
    final bytes = await rootBundle.load(
      'packages/tilawa_flutter/assets/runtime/native.js',
    );
    final script = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final expected = (manifest['artifacts'] as List).cast<Map>().singleWhere(
      (x) => x['name'] == 'native.js',
    );
    if (manifest['upstreamCommit'] != tilawaUpstreamCommit ||
        script.length != expected['bytes'] ||
        sha256.convert(script).toString() != expected['sha256']) {
      throw StateError('Native bridge integrity mismatch');
    }
    worker = _InferenceWorker();
    await worker!.open(assets.files, config);
    final options = jsonEncode({
      'minWordFraction': config.minWordFraction,
      'enableFallback': config.enableFallback,
      'fallbackMaxDistance': config.fallbackMaxDistance,
      'stayOnSurah': config.stayOnSurah,
      'tailSeconds': config.tailDuration.inMicroseconds / 1000000,
      'debug': config.diagnostics,
    });
    final html =
        '''<!doctype html><meta charset="utf-8"><script>
window.sendMessage=(channel,value)=>TilawaNative.postMessage(value);
</script><script src="native.js"></script><script>
let queue=Promise.resolve();
window.hybridCall=(id,method,data)=>{
  queue=queue.then(async()=>{
    if(method==='feed'){
      const raw=atob(data.pcm), buffer=new ArrayBuffer(raw.length), view=new DataView(buffer);
      for(let i=0;i<raw.length;i++)view.setUint8(i,raw.charCodeAt(i));
      const pcm=new Float32Array(raw.length/4);
      for(let i=0;i<pcm.length;i++)pcm[i]=view.getFloat32(i*4,true);
      data={pcm};
    }
    return nativeOperation(method,data);
  }).then(result=>TilawaNative.postMessage(JSON.stringify({kind:'reply',id,result})),
    error=>TilawaNative.postMessage(JSON.stringify({kind:'reply',id,error:String(error)})));
};
(async()=>{
  const [corpus,io]=await Promise.all(['corpus.json','io.json'].map(async name=>{
    const response=await fetch(name);if(!response.ok)throw Error('Local '+name);return response.json();
  }));
  await nativeOperation('initialize',{...$options,corpus,io});
  TilawaNative.postMessage(JSON.stringify({kind:'ready'}));
})().catch(error=>TilawaNative.postMessage(JSON.stringify({kind:'error',error:String(error)})));
</script>''';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final prefix = newTilawaId();
    final origin = Uri.parse('http://127.0.0.1:${server!.port}/$prefix/');
    requests = server!.listen(
      (request) => unawaited(() async {
        try {
          final name = request.uri.path.substring('/$prefix/'.length);
          request.response.headers.set('Cache-Control', 'no-store');
          if (!request.uri.path.startsWith('/$prefix/')) {
            request.response.statusCode = 404;
          } else if (name == 'index.html') {
            request.response.headers.contentType = ContentType.html;
            request.response.write(html);
          } else if (name == 'native.js') {
            request.response.headers.set('Content-Type', 'text/javascript');
            request.response.add(script);
          } else if (name == 'corpus.json' || name == 'io.json') {
            request.response.headers.contentType = ContentType.json;
            await request.response.addStream(assets.files[name]!.openRead());
          } else {
            request.response.statusCode = 404;
          }
        } catch (_) {
          /* A closed browser may cancel the local response. */
        } finally {
          try {
            await request.response.close();
          } catch (_) {}
        }
      }()),
    );
    controller = WebViewController();
    await controller!.setJavaScriptMode(JavaScriptMode.unrestricted);
    router.receive = receive;
    final messages = router;
    await controller!.addJavaScriptChannel(
      'TilawaNative',
      onMessageReceived: (message) => messages.receive?.call(message.message),
    );
    await controller!.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return request.url == 'about:blank' ||
                  (uri?.scheme == origin.scheme &&
                      uri?.host == origin.host &&
                      uri?.port == origin.port &&
                      uri!.path.startsWith(origin.path))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) fail(error.description);
        },
      ),
    );
    await controller!.loadRequest(origin.resolve('index.html'));
    await ready.future.timeout(const Duration(seconds: 30));
  }

  void fail(String message) {
    final error = TilawaException('bridgeDisconnected', message);
    if (!ready.isCompleted) ready.completeError(error);
    for (final operation in pending.values) {
      operation.completeError(error);
    }
    pending.clear();
    if (!closing) sink({'type': '_runtime_failure', 'message': message});
  }

  void receive(String message) {
    try {
      final data = Map<String, Object?>.from(jsonDecode(message) as Map);
      switch (data['kind']) {
        case 'ready':
          if (!ready.isCompleted) ready.complete();
        case 'event':
          if (!closing) sink(Map<String, Object?>.from(data['event'] as Map));
        case 'reply':
          final operation = pending.remove(data['id']);
          if (operation == null) return;
          if (data['error'] != null) {
            operation.completeError(StateError('${data['error']}'));
          } else {
            operation.complete(
              Map<String, Object?>.from(data['result'] as Map),
            );
          }
        case 'infer':
          unawaited(() async {
            try {
              final result = await worker!.call('infer', data);
              await controller?.runJavaScript(
                'nativeDeliver(${data['id']},${jsonEncode(result)},null)',
              );
            } catch (error) {
              await controller?.runJavaScript(
                'nativeDeliver(${data['id']},null,${jsonEncode('$error')})',
              );
            }
          }());
        case 'error':
          fail('${data['error']}');
      }
    } catch (error) {
      fail('$error');
    }
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> data = const {},
  ]) async {
    final id = ++next, operation = Completer<Map<String, Object?>>();
    pending[id] = operation;
    try {
      await controller!.runJavaScript(
        'hybridCall($id,${jsonEncode(method)},${jsonEncode(data)})',
      );
      return await operation.future;
    } finally {
      pending.remove(id);
    }
  }

  TilawaEngineSnapshot snapshot(Map<String, Object?> value) =>
      TilawaEngineSnapshot(
        consumedSamples: value['samples'] as int,
        trackingState: value['state'] == 'tracking'
            ? TilawaTrackingState.tracking
            : value['state'] == 'searching'
            ? TilawaTrackingState.searching
            : TilawaTrackingState.unknown,
        transcript: value['transcript'] as String,
        score: (value['score'] as num?)?.toDouble(),
        sequence: (value['sequence'] as List?)?.map(
          (x) => TilawaSequenceVerse(
            TilawaAyahRef(x['surah'] as int, x['ayah'] as int),
            (x['confidence'] as num).toDouble(),
          ),
        ),
      );
  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async => snapshot(
    await call('feed', {
      'pcm': base64Encode(
        pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
      ),
    }),
  );
  @override
  Future<TilawaEngineSnapshot> stop() async => snapshot(await call('stop'));
  @override
  Future<TilawaEngineSnapshot> reset() async {
    await worker!.call('reset');
    return snapshot(await call('reset'));
  }

  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async =>
      (await call('wordCount', {
            'surah': ayah.surah,
            'ayah': ayah.ayah,
          }))['words']
          as int;
  @override
  Future<void> dispose() => disposal ??= () async {
    closing = true;
    Object? failure;
    try {
      if (ready.isCompleted && controller != null) {
        await call('dispose').timeout(const Duration(seconds: 10));
      }
    } catch (error) {
      failure = error;
    }
    try {
      await worker?.dispose();
    } catch (error) {
      failure = error;
    }
    try {
      await controller?.loadRequest(Uri.parse('about:blank'));
    } catch (error) {
      failure = error;
    }
    router.receive = null;
    controller = null;
    await requests?.cancel();
    await server?.close(force: true);
    if (failure != null) throw failure;
  }();
}

final class _InferenceWorker {
  final port = ReceivePort();
  final commands = Completer<SendPort>();
  final pending = <int, Completer<Object?>>{};
  Isolate? isolate;
  int next = 0;
  Future<void>? disposal;
  bool exited = false;
  Future<void> open(
    Map<String, File> files,
    TilawaRecognitionConfig config,
  ) async {
    commands.future.ignore();
    port.listen((dynamic message) {
      if (message is SendPort) {
        commands.complete(message);
        return;
      }
      if (message == null || message is List) {
        exited = true;
        final error = StateError('Inference worker exited: $message');
        if (!commands.isCompleted) commands.completeError(error);
        for (final operation in pending.values) {
          operation.completeError(error);
        }
        pending.clear();
        return;
      }
      final data = message as Map, operation = pending.remove(data['id']);
      if (operation == null) return;
      if (data['error'] != null) {
        operation.completeError(StateError('${data['error']}'));
      } else {
        operation.complete(data['result']);
      }
    });
    isolate = await Isolate.spawn(
      _inferenceEntry,
      [port.sendPort, ServicesBinding.rootIsolateToken!],
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    await commands.future.timeout(const Duration(seconds: 30));
    await call('open', {
      'files': files.map((name, file) => MapEntry(name, file.path)),
      'config': config,
    }).timeout(const Duration(seconds: 30));
  }

  Future<Object?> call(String method, [Object? data]) async {
    if (exited) throw StateError('Inference worker unavailable');
    final id = ++next, operation = Completer<Object?>();
    pending[id] = operation;
    (await commands.future).send({'id': id, 'method': method, 'data': data});
    return operation.future;
  }

  Future<void> dispose() => disposal ??= () async {
    if (!commands.isCompleted) {
      isolate?.kill(priority: Isolate.immediate);
      port.close();
      return;
    }
    await call('dispose');
    port.close();
    isolate?.kill(priority: Isolate.immediate);
  }();
}

Future<void> _inferenceEntry(List<Object?> args) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    args[1] as RootIsolateToken,
  );
  final root = args[0] as SendPort, commands = ReceivePort();
  final core = NativeCoreAdapter((_) {});
  root.send(commands.sendPort);
  Future<void> queue = Future.value();
  commands.listen((dynamic request) {
    final message = request as Map;
    queue = queue.then((_) async {
      try {
        Object? result;
        switch (message['method']) {
          case 'open':
            final data = message['data'] as Map;
            await core.initializeFiles(
              (data['files'] as Map<String, String>).map(
                (name, path) => MapEntry(name, File(path)),
              ),
              data['config'] as TilawaRecognitionConfig,
              '',
              matching: false,
            );
          case 'infer':
            await core.infer(
              Map<String, dynamic>.from(message['data'] as Map),
              deliver: (value, error) {
                if (error != null) throw StateError(error);
                result = value;
              },
            );
          case 'reset':
            await core.resetStates();
          case 'dispose':
            await core.dispose();
            commands.close();
          default:
            throw StateError('Unknown inference worker operation');
        }
        root.send({'id': message['id'], 'result': result});
      } catch (error) {
        root.send({'id': message['id'], 'error': '$error'});
      }
    });
  });
}
