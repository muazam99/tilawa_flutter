// Private Android Phase 5D validation. Audio fixtures remain ignored/private.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/microphone.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
// Private instrumentation wraps the real implementation, never example code.
// ignore: implementation_imports
import 'package:tilawa_flutter/src/runtime/webview_adapter.dart';

import 'audio_fixture.dart';

void main() => runApp(const MaterialApp(home: _PerformanceProbe()));

class _PerformanceProbe extends StatefulWidget {
  const _PerformanceProbe();
  @override
  State<_PerformanceProbe> createState() => _PerformanceProbeState();
}

class _PerformanceProbeState extends State<_PerformanceProbe> {
  static const native = MethodChannel(
    'dev.qiyam.tilawa_bridge_probe/diagnostics',
  );
  final lines = <String>[];
  TilawaSession? session;
  bool stopRequested = false;
  bool running = true;
  void log(String label, Map<String, Object?> data) {
    final line = '$label ${jsonEncode(data)}';
    debugPrint('TILAWA_PERF $line');
    if (mounted) {
      setState(() {
        lines.add(line);
        if (lines.length > 40) lines.removeAt(0);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
  }

  Future<void> sample(String stage) async {
    final value = await native.invokeMapMethod<String, dynamic>('snapshot');
    log('MEMORY', {
      'stage': stage,
      'appPssKiB': value?['appPssKiB'],
      'interactive': value?['interactive'],
      'keyguardLocked': value?['keyguardLocked'],
    });
  }

  Future<void> requireForeground() async {
    final value = await native.invokeMapMethod<String, dynamic>('snapshot');
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        value?['interactive'] != true ||
        value?['keyguardLocked'] != false) {
      throw StateError('Validation requires unlocked foreground phone');
    }
  }

  Future<void> run() async {
    const mode = String.fromEnvironment(
      'PROBE_VALIDATION',
      defaultValue: 'broader',
    );
    try {
      log('BEGIN', {'mode': mode, 'upstream': tilawaUpstreamCommit});
      await requireForeground();
      await sample('before-assets');
      final support = await getApplicationSupportDirectory();
      final store = TilawaAssetStore(
        Directory('${support.path}/tilawa-sdk-assets'),
      );
      final watch = Stopwatch()..start();
      var assets = await store.available(TilawaAssetManifest.zipformerV1());
      log('ASSET_VERIFY', {
        'elapsedMs': watch.elapsedMilliseconds,
        'reused': assets != null,
      });
      assets ??= await store.fromBundled(TilawaAssetManifest.zipformerV1(), {
        for (final file in TilawaAssetManifest.zipformerV1().files)
          file.name: 'assets/runtime/${file.name}',
      }).completed;
      if (mode == 'broader') {
        await broader(assets);
      } else if (mode == 'resources') {
        await resources(assets);
      } else if (mode == 'switch-only') {
        await switching(assets);
      } else {
        throw StateError('Unknown validation mode');
      }
      log('COMPLETE', {'mode': mode, 'stoppedByUser': stopRequested});
    } catch (error, stack) {
      log('ERROR', {'message': '$error'});
      debugPrint('$stack');
    } finally {
      await session?.dispose();
      if (mounted) setState(() => running = false);
    }
  }

  Future<Float32List> load(String asset) async =>
      decodeAudioFixture(await rootBundle.load(asset));

  Future<void> broader(TilawaPreparedAssets assets) async {
    final manifest =
        jsonDecode(
              await rootBundle.loadString(
                'assets/runtime/validation_samples.json',
              ),
            )
            as Map;
    if (manifest['upstreamCommit'] != tilawaUpstreamCommit) {
      throw StateError('Wrong benchmark baseline');
    }
    session = await TilawaSession.open(
      assets: assets,
      config: const TilawaRecognitionConfig(diagnostics: true),
    );
    Float32List? longAyah, falaq, beginning;
    for (final sample in manifest['samples'] as List) {
      if (stopRequested) break;
      final pcm = await load(sample['asset'] as String);
      final id = sample['id'] as String;
      if (id == 'ref_002255') longAyah = pcm;
      if (id == 'multi_113_001_005') falaq = pcm;
      if (id == 'ref_001002') beginning = pcm;
      await passage(id, pcm, [
        sample['expected_verses'],
        ...?sample['also_accept'] as List?,
      ]);
    }
    if (!stopRequested) {
      await passage(
        'mid-ayah-002255',
        Float32List.sublistView(longAyah!, (longAyah.length * 0.4).round()),
        [
          [
            {'surah': 2, 'ayah': 255},
          ],
        ],
      );
      final noisy = Float32List(falaq!.length);
      final random = Random(20261013);
      for (var i = 0; i < noisy.length; i++) {
        noisy[i] = (falaq[i] * 0.35 + (random.nextDouble() * 2 - 1) * 0.025)
            .clamp(-1, 1);
      }
      await passage('falaq-attenuated-seeded-noise', noisy, [
        [
          for (var ayah = 1; ayah <= 5; ayah++) {'surah': 113, 'ayah': ayah},
        ],
      ]);
      await passage('silence-three-seconds', Float32List(48000), [[]]);
      final switched = Float32List(beginning!.length * 2 + 16000 + falaq.length)
        ..setRange(0, beginning.length, beginning)
        ..setRange(beginning.length, beginning.length * 2, beginning)
        ..setRange(
          beginning.length * 2 + 16000,
          beginning.length * 2 + 16000 + falaq.length,
          falaq,
        );
      await passage('repeat-beginning-silence-switch-falaq', switched, [
        [
          {'surah': 1, 'ayah': 2},
          for (var ayah = 1; ayah <= 5; ayah++) {'surah': 113, 'ayah': ayah},
        ],
      ]);
    }
    await session!.dispose();
    session = null;
  }

  Future<void> switching(TilawaPreparedAssets assets) async {
    final first = await load('assets/runtime/validation_ref_002255.audio');
    final second = await load(
      'assets/runtime/validation_multi_113_001_005.audio',
    );
    final combined = Float32List(first.length * 2 + 16000 + second.length)
      ..setRange(0, first.length, first)
      ..setRange(first.length, first.length * 2, first)
      ..setRange(
        first.length * 2 + 16000,
        first.length * 2 + 16000 + second.length,
        second,
      );
    session = await TilawaSession.open(
      assets: assets,
      config: const TilawaRecognitionConfig(diagnostics: true),
    );
    await passage('repeat-tracked-002255-silence-switch-falaq', combined, [
      [
        {'surah': 2, 'ayah': 255},
        for (var ayah = 1; ayah <= 5; ayah++) {'surah': 113, 'ayah': ayah},
      ],
    ]);
    await session!.dispose();
    session = null;
  }

  Future<void> passage(
    String id,
    Float32List pcm,
    List<dynamic> accepted,
  ) async {
    await session!.reset();
    await requireForeground();
    var matches = 0, progress = 0;
    final candidates = <String>{};
    var fallbackMatches = 0;
    final diagnostics = <String, int>{};
    final events = session!.events.listen((event) {
      if (event is TilawaVerseMatched) matches++;
      if (event is TilawaWordProgress) progress++;
      if (event is TilawaVerseCandidates) {
        for (final candidate in event.candidates) {
          candidates.add('${candidate.ayah}');
        }
      }
      if (event is TilawaDiagnostic) {
        if (event.name == 'fallback') fallbackMatches++;
        diagnostics.update(event.name, (count) => count + 1, ifAbsent: () => 1);
      }
    });
    final clock = Stopwatch()..start();
    for (
      var offset = 0;
      offset < pcm.length && !stopRequested;
      offset += 7680
    ) {
      await session!.feed(
        Float32List.sublistView(pcm, offset, min(offset + 7680, pcm.length)),
      );
    }
    final result = await session!.stop();
    await Future<void>.delayed(Duration.zero);
    await events.cancel();
    final actual = result.engineSequence?.map((v) => '${v.ayah}').toList();
    final expected = accepted
        .map(
          (sequence) => (sequence as List)
              .map((v) => '${v['surah']}:${v['ayah']}')
              .toList(),
        )
        .toList();
    log('PASSAGE', {
      'id': id,
      'inputSamples': pcm.length,
      'audioSeconds': pcm.length / 16000,
      'elapsedMs': clock.elapsedMilliseconds,
      'expectedAlternatives': expected,
      'actual': actual,
      'sequenceScore': result.sequenceScore,
      'verseScores': result.engineSequence
          ?.map((verse) => verse.score)
          .toList(),
      'expectedSequence': expected.any(
        (refs) => jsonEncode(refs) == jsonEncode(actual),
      ),
      'matches': matches,
      'progress': progress,
      'candidates': candidates.toList(),
      'diagnosticFallbackMentions': fallbackMatches,
      'diagnostics': diagnostics,
      'finalization': result.finalization.name,
      'processedSamples': result.processedSamples,
    });
  }

  Future<void> resources(TilawaPreparedAssets assets) async {
    await sample('before-decode');
    final pcm = await load('assets/runtime/validation_multi_113_001_005.audio');
    await sample('after-decode');
    var factory = _MeasuredFactory();
    final open = Stopwatch()..start();
    session = await TilawaSession.open(assets: assets, adapterFactory: factory);
    log('OPEN', {
      'cycle': 0,
      'elapsedMs': open.elapsedMilliseconds,
      'adapterInitializeMs': factory.initializeMs,
    });
    await sample('first-open');
    await paced(pcm, factory);
    await session!.reset();
    factory.timings.clear();
    await microphone(factory);
    await session!.dispose();
    session = null;
    await sample('first-dispose');
    for (var cycle = 1; cycle <= 5 && !stopRequested; cycle++) {
      factory = _MeasuredFactory();
      open.reset();
      session = await TilawaSession.open(
        assets: assets,
        adapterFactory: factory,
      );
      log('OPEN', {
        'cycle': cycle,
        'elapsedMs': open.elapsedMilliseconds,
        'adapterInitializeMs': factory.initializeMs,
      });
      await sample('recreate-$cycle-open');
      for (var offset = 0; offset < 32000; offset += 7680) {
        await session!.feed(Float32List(min(7680, 32000 - offset)));
      }
      await session!.stop();
      await session!.reset();
      await session!.feed(Float32List(7680));
      await session!.stop();
      await session!.dispose();
      session = null;
      await sample('recreate-$cycle-disposed');
    }
    await Future<void>.delayed(const Duration(seconds: 15));
    await sample('settled');
  }

  Future<void> paced(Float32List pcm, _MeasuredFactory factory) async {
    const totalSamples = 300 * 16000;
    final clock = Stopwatch()..start();
    var samples = 0, nextReport = 30, maxLagMs = 0;
    log('PACED_BEGIN', {
      'plannedSeconds': 300,
      'fixture': 'multi_113_001_005',
      'producer': 'bounded sequential 480ms chunks',
    });
    while (samples < totalSamples && !stopRequested) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        throw StateError('Paced probe left foreground');
      }
      final length = min(7680, totalSamples - samples);
      final chunk = Float32List(length);
      for (var i = 0; i < length; i++) {
        chunk[i] = pcm[(samples + i) % pcm.length];
      }
      final dueMs = ((samples + length) / 16).round();
      final wait = dueMs - clock.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      await session!.feed(chunk);
      maxLagMs = max(maxLagMs, clock.elapsedMilliseconds - dueMs);
      samples += length;
      if (clock.elapsed.inSeconds >= nextReport) {
        log('PACED_TICK', {
          'elapsedMs': clock.elapsedMilliseconds,
          'processedSamples': session!.snapshot.processedSamples,
          'maxCompletionLagMs': maxLagMs,
          ...factory.summary(),
        });
        await sample('paced-$nextReport');
        nextReport += 30;
      }
    }
    final flush = Stopwatch()..start();
    final result = await session!.stop();
    log('PACED_END', {
      'elapsedMs': clock.elapsedMilliseconds,
      'submittedSamples': result.submittedSamples,
      'processedSamples': result.processedSamples,
      'flushMs': flush.elapsedMilliseconds,
      'finalization': result.finalization.name,
      'maxCompletionLagMs': maxLagMs,
      'fiveMinutesInput': samples == totalSamples,
      ...factory.summary(),
    });
  }

  Future<void> microphone(_MeasuredFactory factory) async {
    if (stopRequested) return;
    final mic = await TilawaMicrophone.open(session: session!);
    var errors = 0, highWaterSamples = 0;
    final subscription = mic.errors.listen((error) {
      errors++;
      log('CAPTURE_ERROR', {'code': error.code});
    });
    final poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final current = session!.snapshot;
      highWaterSamples = max(
        highWaterSamples,
        current.submittedSamples - current.processedSamples,
      );
    });
    try {
      await mic.start();
      final clock = Stopwatch()..start();
      final format = await native.invokeMapMethod<String, dynamic>('snapshot');
      log('MIC_BEGIN', {
        'plannedSeconds': 300,
        'recordings': format?['recordings'],
        'queueCapacityChunks': 4,
      });
      var nextReport = 30;
      while (clock.elapsed.inSeconds < 300 && !stopRequested) {
        if (mic.state != TilawaCaptureState.capturing) {
          throw StateError('Sustained capture interrupted: ${mic.state}');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        if (clock.elapsed.inSeconds >= nextReport) {
          log('MIC_TICK', {
            'elapsedMs': clock.elapsedMilliseconds,
            'submittedSamples': session!.snapshot.submittedSamples,
            'processedSamples': session!.snapshot.processedSamples,
            'sampledOutstandingHighWater': highWaterSamples,
            'errors': errors,
            ...factory.summary(),
          });
          await sample('mic-$nextReport');
          nextReport += 30;
        }
      }
      final captureElapsedMs = clock.elapsedMilliseconds;
      await mic.stopCapture();
      final flush = Stopwatch()..start();
      final result = await session!.stop();
      log('MIC_END', {
        'captureElapsedMs': captureElapsedMs,
        'submittedSamples': result.submittedSamples,
        'processedSamples': result.processedSamples,
        'inputSeconds': result.processedSamples / 16000,
        'sampledOutstandingHighWater': highWaterSamples,
        'errors': errors,
        'flushMs': flush.elapsedMilliseconds,
        'finalization': result.finalization.name,
        'fiveMinutesCapture': captureElapsedMs >= 300000,
        ...factory.summary(),
      });
    } finally {
      poll.cancel();
      await mic.dispose();
      await subscription.cancel();
    }
  }

  @override
  void dispose() {
    stopRequested = true;
    unawaited(session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Private Android validation')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Opt-in validation. Resources mode runs five minutes paced input, then five minutes foreground microphone. Keep foregrounded. No live audio/transcript is saved.',
          ),
        ),
        ElevatedButton(
          onPressed: running
              ? () => setState(() => stopRequested = true)
              : null,
          child: const Text('Stop validation'),
        ),
        Expanded(
          child: ListView(
            reverse: true,
            children: lines.reversed
                .map(
                  (line) => Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(line),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );
}

final class _MeasuredFactory implements TilawaEngineAdapterFactory {
  int initializeMs = 0;
  final timings = <int>[];
  Map<String, Object?> summary() {
    final sorted = [...timings]..sort();
    return {
      'feedCalls': timings.length,
      'meanFeedMs': timings.isEmpty
          ? 0
          : timings.reduce((a, b) => a + b) / timings.length,
      'p95FeedMs': sorted.isEmpty
          ? 0
          : sorted[min(sorted.length - 1, (sorted.length * 0.95).ceil() - 1)],
      'maxFeedMs': sorted.isEmpty ? 0 : sorted.last,
    };
  }

  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async {
    final clock = Stopwatch()..start();
    final inner = await const TilawaWebViewAdapterFactory().create(
      assets,
      config,
      sink,
    );
    initializeMs = clock.elapsedMilliseconds;
    return _MeasuredAdapter(inner, timings);
  }
}

final class _MeasuredAdapter implements TilawaEngineAdapter {
  _MeasuredAdapter(this.inner, this.timings);
  final TilawaEngineAdapter inner;
  final List<int> timings;
  @override
  String get id => inner.id;
  @override
  String get version => inner.version;
  @override
  TilawaCapabilities get capabilities => inner.capabilities;
  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async {
    final clock = Stopwatch()..start();
    try {
      return await inner.feed(pcm);
    } finally {
      timings.add(clock.elapsedMilliseconds);
    }
  }

  @override
  Future<TilawaEngineSnapshot> stop() => inner.stop();
  @override
  Future<TilawaEngineSnapshot> reset() => inner.reset();
  @override
  Future<int> describeAyah(TilawaAyahRef ayah) => inner.describeAyah(ayah);
  @override
  Future<void> dispose() => inner.dispose();
}
