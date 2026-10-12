// Private Phase 3 validation surface. Not the Phase 5 public example.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

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
      final pcm = _wav(bytes);
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

  Float32List _wav(ByteData data) {
    String tag(int offset) => String.fromCharCodes(
      List.generate(4, (i) => data.getUint8(offset + i)),
    );
    if (data.lengthInBytes < 44 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw StateError('Fixture is not RIFF WAV.');
    }
    var rate = 0, channels = 0, bits = 0, format = 0, start = 0, size = 0;
    for (var offset = 12; offset + 8 <= data.lengthInBytes;) {
      final length = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (body + length > data.lengthInBytes) {
        throw StateError('Truncated WAV.');
      }
      if (tag(offset) == 'fmt ') {
        if (length < 16) throw StateError('Invalid WAV format block.');
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        rate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      }
      if (tag(offset) == 'data') {
        start = body;
        size = length;
      }
      offset = body + length + (length % 2);
    }
    _log('WAV_FORMAT pcm=$format rate=$rate channels=$channels bits=$bits');
    if (format != 1 ||
        rate != 16000 ||
        channels != 1 ||
        bits != 16 ||
        start == 0 ||
        size.isOdd) {
      throw StateError(
        'Private replay supports only mono 16 kHz PCM16 WAV; convert externally otherwise.',
      );
    }
    return Float32List.fromList(
      List.generate(
        size ~/ 2,
        (i) => data.getInt16(start + i * 2, Endian.little) / 32768,
      ),
    );
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
