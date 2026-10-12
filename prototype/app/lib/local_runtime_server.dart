import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Private same-device asset server. It never binds to a LAN interface.
class LocalRuntimeServer {
  HttpServer? _server;
  late Uri origin;
  late String _prefix;
  final Map<String, File> _files = {};

  Future<void> start() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/runtime-2f261746-ort1242');
    await directory.create(recursive: true);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets()) {
      if (!asset.startsWith('assets/runtime/')) continue;
      final name = asset.substring('assets/runtime/'.length);
      if (name.contains('/')) continue;
      final file = File('${directory.path}/$name');
      // Always refresh code; immutable large model/corpus can be reused.
      if (!await file.exists() ||
          !['model.onnx', 'corpus.json'].contains(name)) {
        final data = await rootBundle.load(asset);
        final partial = File('${file.path}.partial');
        await partial.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        if (await file.exists()) await file.delete();
        await partial.rename(file.path);
      }
      _files[name] = file;
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    _prefix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    origin = Uri.parse('http://127.0.0.1:${_server!.port}/$_prefix/');
    _server!.listen(_serve);
  }

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    final name = path.startsWith('/$_prefix/')
        ? path.substring(_prefix.length + 2)
        : '';
    final file = _files[name];
    final response = request.response;
    if (request.method != 'GET' || file == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final mime = name.endsWith('.wasm')
        ? 'application/wasm'
        : name.endsWith('.js') || name.endsWith('.mjs')
        ? 'text/javascript'
        : name.endsWith('.json')
        ? 'application/json'
        : name.endsWith('.html')
        ? 'text/html'
        : 'application/octet-stream';
    response.headers.set(HttpHeaders.contentTypeHeader, mime);
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    response.headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
    response.headers.set('Cross-Origin-Resource-Policy', 'same-origin');
    response.contentLength = await file.length();
    try {
      await response.addStream(file.openRead());
      await response.close();
    } on HttpException {
      // A closed WebView may cancel an in-flight asset request.
    }
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
  }
}
