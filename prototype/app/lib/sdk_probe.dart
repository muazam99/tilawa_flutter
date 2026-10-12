// Private Phase 3 validation surface. Not the Phase 5 public example.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

import 'asset_probe.dart';
import 'audio_fixture.dart';
import 'control_probe.dart';
import 'microphone_probe.dart';

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
      var store = TilawaAssetStore(
        Directory('${support.path}/tilawa-sdk-assets'),
      );
      final manifest = TilawaAssetManifest.zipformerV1();
      TilawaPreparedAssets assets;
      const assetChecks = bool.fromEnvironment('PROBE_ASSETS');
      if (assetChecks) {
        final checked = await runAssetProbe(support, _log);
        store = checked.store;
        assets = checked.assets;
      } else {
        final install = store.fromBundled(manifest, {
          for (final file in manifest.files)
            file.name: 'assets/runtime/${file.name}',
        });
        assets = await install.completed;
      }
      _log('ASSETS_VERIFIED');
      if (const bool.fromEnvironment('PROBE_CONTROLS')) {
        await runControlProbe(assets, _log);
      }
      session = await TilawaSession.open(assets: assets);
      _log('SDK_READY adapter=${session.info.adapterId}');
      if (assetChecks) {
        await expectAssetError('assetsInUse', () => store.delete(manifest));
        _log('ASSET_SESSION_LEASE deleteBlocked=true');
      }
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
      final pcm = await decodeAudioFixture(bytes);
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
      if (assetChecks) {
        await store.delete(manifest);
        requireAssetProbe(
          await store.available(manifest) == null,
          'Disposed runtime retained its asset lease',
        );
        _log('ASSET_SESSION_RELEASE deleteAllowed=true');
        _log('ASSET_CHECKS_COMPLETE');
      }
      _log('SDK_COMPLETE');
      if (const bool.fromEnvironment('PROBE_MIC') && mounted) {
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MicrophoneProbe(assets: assets),
            ),
          ),
        );
      }
    } catch (error, stack) {
      _log('ERROR $error');
      debugPrint('$stack');
    } finally {
      await session?.dispose();
      await events?.cancel();
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
