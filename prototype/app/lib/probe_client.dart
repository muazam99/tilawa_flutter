import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// Private request/reply bridge with upstream observations on one event path.
class ProbeClient {
  final WebViewController controller = WebViewController();
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 0;
  bool _closed = false;

  Stream<Map<String, dynamic>> get messages => _messages.stream;

  Future<void> attach(Uri origin) async {
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'TilawaProbe',
      onMessageReceived: (message) {
        if (_closed) return;
        final parsed = Map<String, dynamic>.from(
          jsonDecode(message.message) as Map,
        );
        if (parsed['kind'] == 'reply') {
          final completer = _pending.remove(parsed['id']);
          if (completer == null) return;
          if (parsed.containsKey('error')) {
            completer.completeError(StateError('${parsed['error']}'));
          } else {
            completer.complete(parsed['result']);
          }
        } else {
          _messages.add(parsed);
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) =>
            request.url.startsWith(origin.toString())
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onWebResourceError: (error) => _messages.add({
          'kind': 'runtime_error',
          'error': error.description,
        }),
      ),
    );
    await controller.loadRequest(origin.resolve('index.html').replace(queryParameters: {
      'threads': const String.fromEnvironment('PROBE_THREADS', defaultValue: '1'),
    }));
  }

  Future<dynamic> call(String method, [Map<String, dynamic>? data]) async {
    if (_closed) throw StateError('Bridge is closed');
    final id = ++_nextId;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    try {
      await controller.runJavaScript(
        'window.probeDispatch(${jsonEncode({'id': id, 'method': method, 'data': data})});',
      );
      return await completer.future.timeout(const Duration(minutes: 3));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final pending in _pending.values) {
      pending.completeError(StateError('Bridge was closed'));
    }
    _pending.clear();
    await controller.loadHtmlString('<html><body>Disposed</body></html>');
    await _messages.close();
  }
}
