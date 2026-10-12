// Private Phase 3 validation surface. Not the Phase 5 public example.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const MaterialApp(home: _SdkProbe()));

class _SdkProbe extends StatefulWidget {
  const _SdkProbe();
  @override
  State<_SdkProbe> createState() => _SdkProbeState();
}

class _SdkProbeState extends State<_SdkProbe> {
  final _lines = <String>[];
  void _log(String message) {
    debugPrint('TILAWA_SDK $message');
    if (mounted) setState(() => _lines.add(message));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    TilawaSession? session;
    StreamSubscription<TilawaEvent>? events;
    try {
      final support = await getApplicationSupportDirectory();
      final store = TilawaAssetStore(
        Directory('${support.path}/tilawa-sdk-assets'),
      );
      final manifest = TilawaAssetManifest.zipformerV1();
      final install = store.fromBundled(manifest, {
        for (final file in manifest.files)
          file.name: 'assets/runtime/${file.name}',
      });
      final assets = await install.completed;
      _log('ASSETS_VERIFIED');
      session = await TilawaSession.open(assets: assets);
      _log('SDK_READY adapter=${session.info.adapterId}');
      var matches = 0, progress = 0;
      TilawaSessionResult? eventResult;
      events = session.events.listen((event) {
        if (event is TilawaVerseMatched) matches++;
        if (event is TilawaWordProgress) progress++;
        if (event is TilawaSessionEnded) eventResult = event.result;
        if (event is TilawaFailure) _log('FAILURE ${event.error}');
      });
      final bytes = await rootBundle.load(
        'assets/runtime/multi_113_001_005.audio',
      );
      final pcm = await _decode(bytes);
      _log('WAV_PCM samples=${pcm.length}');
      for (var offset = 0; offset < pcm.length; offset += 7680) {
        await session.feed(
          Float32List.sublistView(pcm, offset, min(offset + 7680, pcm.length)),
        );
      }
      final result = await session.stop();
      final again = await session.stop();
      await Future<void>.delayed(Duration.zero);
      _log(
        'RESULT ${result.engineSequence?.map((verse) => verse.ayah).join(',')} matches=$matches progress=$progress '
        'samples=${result.processedSamples} sameStop=${identical(result, again)} sameEvent=${identical(result, eventResult)}',
      );
      await session.reset();
      await session.feed(Float32List(16000));
      final silence = await session.stop();
      _log(
        'SILENCE verses=${silence.engineSequence?.length} run=${silence.runId != result.runId}',
      );
      await session.dispose();
      session = null;
      _log('SDK_DISPOSED');
      final reused = await store.available(manifest);
      _log('OFFLINE_REUSE ${reused != null}');
      _log('SDK_COMPLETE');
    } catch (error, stack) {
      _log('ERROR $error');
      debugPrint('$stack');
    } finally {
      await session?.dispose();
      await events?.cancel();
    }
  }

  Future<Float32List> _decode(ByteData data) async {
    // External input preparation only, using Phase 1's Web Audio conversion.
    // No microphone, network or private inference adapter API is involved.
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tilawa SDK probe')),
    body: ListView(
      children: _lines
          .map(
            (line) =>
                Padding(padding: const EdgeInsets.all(8), child: Text(line)),
          )
          .toList(),
    ),
  );
}
