// External input preparation, shared by private public-SDK consumers.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_flutter/webview_flutter.dart';

Future<Float32List> decodeAudioFixture(ByteData data) async {
  final controller = WebViewController();
  final ready = Completer<void>();
  final result = Completer<String>();
  ready.future.ignore();
  result.future.ignore();
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.addJavaScriptChannel(
    'Fixture',
    onMessageReceived: (message) {
      if (message.message == 'ready') {
        if (!ready.isCompleted) ready.complete();
      } else if (!result.isCompleted) {
        if (message.message.startsWith('error:')) {
          result.completeError(StateError(message.message));
        } else {
          result.complete(message.message);
        }
      }
    },
  );
  try {
    await controller.loadHtmlString('''<html><body><script>
window.decodeFixture = async function(encoded) {
  try {
    const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    const context = new AudioContext();
    let decoded;
    try { decoded = await context.decodeAudioData(bytes.buffer); }
    finally { await context.close(); }
    const offline = new OfflineAudioContext(1, Math.ceil(decoded.duration * 16000), 16000);
    const source = offline.createBufferSource(); source.buffer = decoded;
    source.connect(offline.destination); source.start();
    const pcm = (await offline.startRendering()).getChannelData(0);
    const output = new Uint8Array(pcm.length * 4), view = new DataView(output.buffer);
    for (let i = 0; i < pcm.length; i++) view.setFloat32(i * 4, pcm[i], true);
    let binary = '';
    for (let i = 0; i < output.length; i += 4096) {
      binary += String.fromCharCode(...output.subarray(i, i + 4096));
    }
    Fixture.postMessage(btoa(binary));
  } catch (error) { Fixture.postMessage('error:' + error); }
};
Fixture.postMessage('ready');
</script></body></html>''');
    await ready.future.timeout(const Duration(seconds: 15));
    final encoded = base64Encode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    await controller.runJavaScript(
      'window.decodeFixture(${jsonEncode(encoded)});',
    );
    final decoded = ByteData.sublistView(
      base64Decode(await result.future.timeout(const Duration(seconds: 30))),
    );
    return Float32List.fromList(
      List.generate(
        decoded.lengthInBytes ~/ 4,
        (i) => decoded.getFloat32(i * 4, Endian.little),
      ),
    );
  } finally {
    await controller.loadHtmlString('<html><body></body></html>');
  }
}
