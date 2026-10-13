import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../adapter.dart';
import '../assets.dart';
import '../models.dart';

final class TilawaWebViewAdapterFactory implements TilawaEngineAdapterFactory {
  const TilawaWebViewAdapterFactory({this.disposeController});
  // Private native-teardown diagnostic seam, not exported by public barrels.
  final Future<void> Function(WebViewController)? disposeController;
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink observationSink,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw const TilawaException(
        'unsupportedPlatform',
        'Default runtime supports Android/iOS only.',
      );
    }
    final manifest = assets.manifest;
    if (manifest.engineId != 'zipformer' ||
        manifest.upstreamCommit != tilawaUpstreamCommit ||
        manifest.segmentationId != tilawaSegmentationId ||
        manifest.corpusSha256 != tilawaCorpusSha256 ||
        manifest.ioSchema != 'zipformer-a0w-ep1-a05' ||
        manifest.file('model.onnx').sha256 !=
            TilawaAssetManifest.zipformerV1().file('model.onnx').sha256 ||
        manifest.file('io.json').sha256 !=
            TilawaAssetManifest.zipformerV1().file('io.json').sha256) {
      throw const TilawaException(
        'incompatibleAssets',
        'Default adapter requires the pinned Zipformer baseline.',
      );
    }
    final adapter = _WebViewAdapter(observationSink, disposeController);
    try {
      await adapter.initialize(assets, config);
      return adapter;
    } catch (_) {
      await adapter.dispose();
      rethrow;
    }
  }
}

final class _WebViewAdapter implements TilawaEngineAdapter {
  _WebViewAdapter(this._sink, this._disposeController);
  final TilawaObservationSink _sink;
  final Future<void> Function(WebViewController)? _disposeController;
  WebViewController? _controller;
  Uri? _origin;
  static _IdleRuntime? _idle;
  final _epoch = newTilawaId();
  Map<String, File>? _files;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final _ready = Completer<void>();
  HttpServer? _server;
  Directory? _runtimeDirectory;
  StreamSubscription<HttpRequest>? _requests;
  int _nextId = 0;
  bool _closed = false;
  TilawaException? _broken;
  @override
  String get id => 'local-webview-wasm';
  @override
  String get version => 'ort-web-1.24.2';
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
    _ready.future
        .ignore(); // Still rethrows to the later await, without a startup race.
    // Android's browser may defer collecting entire WASM realms. Reuse at most
    // one released realm briefly, never a recognition session or asset lease.
    final idle = Platform.isAndroid && _disposeController == null
        ? _idle
        : null;
    if (idle != null) {
      _idle = null;
      idle.expiry.cancel();
      _controller = idle.controller;
      _server = idle.server;
      _requests = idle.requests;
      _runtimeDirectory = idle.directory;
      _files = idle.files..addAll(assets.files);
      _origin = idle.origin;
      await _bindMessages();
      await _bindNavigation(idle.origin);
      _ready.complete();
      await _initializeSession(config);
      return;
    }
    _controller = WebViewController();
    final support = await getApplicationSupportDirectory();
    // Unique resources per opened adapter prevent concurrent refresh/teardown races.
    final runtime = await Directory(
      p.join(support.path, 'tilawa-runtime'),
    ).create(recursive: true);
    _runtimeDirectory = await runtime.createTemp('session-');
    final files = _files = <String, File>{...assets.files};
    final runtimeManifest = Map<String, Object?>.from(
      jsonDecode(
            await rootBundle.loadString(
              'packages/tilawa_flutter/assets/runtime/manifest.json',
            ),
          )
          as Map,
    );
    if (runtimeManifest['upstreamCommit'] != tilawaUpstreamCommit ||
        runtimeManifest['ortVersion'] != '1.24.2') {
      throw const TilawaException(
        'incompatibleAssets',
        'Bundled runtime baseline mismatch.',
      );
    }
    final artifacts = (runtimeManifest['artifacts'] as List).cast<Map>();
    const names = [
      'index.html',
      'bridge.js',
      'ort-wasm-simd-threaded.mjs',
      'ort-wasm-simd-threaded.wasm',
    ];
    for (final name in names) {
      final bytes = await rootBundle.load(
        'packages/tilawa_flutter/assets/runtime/$name',
      );
      final data = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final expected = artifacts.singleWhere(
        (artifact) => artifact['name'] == name,
      );
      if (data.length != expected['bytes'] ||
          sha256.convert(data).toString() != expected['sha256']) {
        throw TilawaException(
          'assetIntegrityMismatch',
          'Bundled runtime integrity mismatch for $name.',
        );
      }
      final file = File(p.join(_runtimeDirectory!.path, name));
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      files[name] = file;
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final prefix = newTilawaId();
    final origin = Uri.parse('http://127.0.0.1:${_server!.port}/$prefix/');
    _origin = origin;
    _requests = _server!.listen(
      (request) => unawaited(_serve(request, prefix, files)),
    );
    await _controller!.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _bindMessages();
    await _bindNavigation(origin);
    await _controller!.loadRequest(origin.resolve('index.html'));
    await _ready.future.timeout(const Duration(seconds: 30));
    await _initializeSession(config);
  }

  Future<void> _bindNavigation(Uri origin) =>
      _controller!.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    uri.scheme == origin.scheme &&
                    uri.host == origin.host &&
                    uri.port == origin.port &&
                    uri.path.startsWith(origin.path)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _disconnect(
                TilawaException('bridgeDisconnected', error.description),
              );
            }
          },
        ),
      );

  Future<void> _bindMessages() => _controller!.addJavaScriptChannel(
    'TilawaSdk',
    onMessageReceived: (message) {
      if (_closed) return;
      try {
        final parsed = Map<String, Object?>.from(
          jsonDecode(message.message) as Map,
        );
        if ((parsed['kind'] == 'event' || parsed['kind'] == 'reply') &&
            parsed['epoch'] != _epoch) {
          return;
        }
        switch (parsed['kind']) {
          case 'ready':
            if (!_ready.isCompleted) _ready.complete();
          case 'event':
            _sink(freezeMap(Map<String, Object?>.from(parsed['event'] as Map)));
          case 'reply':
            final completer = _pending.remove(parsed['id']);
            if (completer == null) return;
            if (parsed['error'] != null) {
              completer.completeError(
                TilawaException('inferenceFailed', '${parsed['error']}'),
              );
            } else {
              completer.complete(
                Map<String, Object?>.from(parsed['result'] as Map),
              );
            }
          case 'error':
            _disconnect(
              TilawaException('bridgeDisconnected', '${parsed['error']}'),
            );
        }
      } catch (error) {
        _disconnect(TilawaException('invalidEngineOutput', '$error'));
      }
    },
  );

  Future<void> _initializeSession(TilawaRecognitionConfig config) async {
    await _call('initialize', {
      'minWordFraction': config.minWordFraction,
      'enableFallback': config.enableFallback,
      'fallbackMaxDistance': config.fallbackMaxDistance,
      'stayOnSurah': config.stayOnSurah,
      'tailSeconds': config.tailDuration.inMicroseconds / 1000000,
      'debug': config.diagnostics,
    });
  }

  static Future<void> _serve(
    HttpRequest request,
    String prefix,
    Map<String, File> files,
  ) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      final name = path.startsWith('/$prefix/')
          ? path.substring(prefix.length + 2)
          : '';
      final file = files[name];
      if (request.method != 'GET' || file == null) {
        response.statusCode = 404;
        return;
      }
      response.headers.set(
        'Content-Type',
        name.endsWith('.wasm')
            ? 'application/wasm'
            : name.endsWith('.js') || name.endsWith('.mjs')
            ? 'text/javascript'
            : name.endsWith('.html')
            ? 'text/html'
            : name.endsWith('.json')
            ? 'application/json'
            : 'application/octet-stream',
      );
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
      response.contentLength = await file.length();
      await response.addStream(file.openRead());
    } catch (_) {
      // Client disposal can cancel an in-flight file response.
    } finally {
      try {
        await response.close();
      } catch (_) {
        /* Connection already closed. */
      }
    }
  }

  void _disconnect(TilawaException error) {
    if (_broken == null) {
      _broken = error;
      if (!_closed) {
        _sink({'type': '_runtime_failure', 'message': error.message});
      }
    }
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
  }

  Future<Map<String, Object?>> _call(
    String method, [
    Map<String, Object?>? data,
  ]) async {
    if (_closed) {
      throw const TilawaException('disposed', 'Runtime is disposed.');
    }
    if (_broken != null && method != 'dispose') throw _broken!;
    final id = ++_nextId;
    final pending = Completer<Map<String, Object?>>();
    _pending[id] = pending;
    try {
      unawaited(
        _controller!
            .runJavaScript(
              'window.tilawaDispatch(${jsonEncode({'id': id, 'epoch': _epoch, 'method': method, 'data': data})});',
            )
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                _pending
                    .remove(id)
                    ?.completeError(
                      TilawaException('bridgeDisconnected', '$error'),
                      stack,
                    );
              },
            ),
      );
      return await pending.future.timeout(const Duration(minutes: 3));
    } finally {
      _pending.remove(id);
    }
  }

  TilawaEngineSnapshot _snapshot(Map<String, Object?> result) {
    final state = result['state'];
    return TilawaEngineSnapshot(
      consumedSamples: result['samples'] as int,
      trackingState: state == 'tracking'
          ? TilawaTrackingState.tracking
          : state == 'searching'
          ? TilawaTrackingState.searching
          : TilawaTrackingState.unknown,
      transcript: result['transcript'] as String,
      score: (result['score'] as num?)?.toDouble(),
      sequence: (result['sequence'] as List?)?.map((item) {
        final verse = item as Map;
        return TilawaSequenceVerse(
          TilawaAyahRef(verse['surah'] as int, verse['ayah'] as int),
          (verse['confidence'] as num).toDouble(),
        );
      }),
    );
  }

  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async {
    final bytes = ByteData(pcm.length * 4);
    for (var i = 0; i < pcm.length; i++) {
      bytes.setFloat32(i * 4, pcm[i], Endian.little);
    }
    return _snapshot(
      await _call('feed', {'pcm': base64Encode(bytes.buffer.asUint8List())}),
    );
  }

  @override
  Future<TilawaEngineSnapshot> stop() async => _snapshot(await _call('stop'));
  @override
  Future<TilawaEngineSnapshot> reset() async => _snapshot(await _call('reset'));
  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async =>
      (await _call('wordCount', {
            'surah': ayah.surah,
            'ayah': ayah.ayah,
          }))['words']
          as int;
  @override
  Future<void> dispose() async {
    if (_closed) return;
    var released = false;
    try {
      await _call('dispose').timeout(const Duration(seconds: 2));
      released = _broken == null;
    } catch (_) {
      /* Teardown remains mandatory. */
    }
    _closed = true;
    _disconnect(const TilawaException('disposed', 'Runtime closed.'));
    final controller = _controller;
    _controller = null;
    if (released &&
        Platform.isAndroid &&
        _disposeController == null &&
        controller != null &&
        _server != null &&
        _requests != null &&
        _runtimeDirectory != null &&
        _files != null) {
      // Remove every recognition-file mapping before the facade releases its
      // installation lease. Cached browser infrastructure must not serve assets
      // belonging to a disposed session or keep its observation callback alive.
      _files!.removeWhere(
        (name, _) => !{
          'index.html',
          'bridge.js',
          'ort-wasm-simd-threaded.mjs',
          'ort-wasm-simd-threaded.wasm',
        }.contains(name),
      );
      await controller.removeJavaScriptChannel('TilawaSdk');
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (_) => NavigationDecision.prevent,
        ),
      );
      final cached = _IdleRuntime(
        controller,
        _server!,
        _requests!,
        _runtimeDirectory!,
        _files!,
        _origin!,
      );
      final previous = _idle;
      _idle = cached;
      cached.expiry = Timer(const Duration(seconds: 15), () {
        if (identical(_idle, cached)) _idle = null;
        unawaited(cached.close().catchError((Object _) {}));
      });
      // Clear adapter ownership. A retained disposed facade cannot retain the
      // cached host, and simultaneous sessions never share an active runtime.
      _server = null;
      _requests = null;
      _runtimeDirectory = null;
      _files = null;
      if (previous != null) {
        previous.expiry.cancel();
        await previous.close();
      }
      return;
    }
    try {
      await controller?.removeJavaScriptChannel('TilawaSdk');
      await controller?.setNavigationDelegate(NavigationDelegate());
      await controller?.loadHtmlString('<html><body></body></html>');
      if (controller != null) await _disposeController?.call(controller);
    } finally {
      await _requests?.cancel();
      await _server?.close(force: true);
      final directory = _runtimeDirectory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
}

final class _IdleRuntime {
  _IdleRuntime(
    this.controller,
    this.server,
    this.requests,
    this.directory,
    this.files,
    this.origin,
  );
  final WebViewController controller;
  final HttpServer server;
  final StreamSubscription<HttpRequest> requests;
  final Directory directory;
  final Map<String, File> files;
  final Uri origin;
  late final Timer expiry;

  Future<void> close() async {
    try {
      await controller.loadHtmlString('<html><body></body></html>');
    } catch (_) {
      // A failed renderer must still lose local transport/files.
    } finally {
      await requests.cancel();
      await server.close(force: true);
      files.clear();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}
