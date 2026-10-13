// Private Android Phase 5D validation. Audio fixtures remain ignored/private.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/microphone.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
// Private instrumentation wraps the real implementation, never example code.
// ignore: implementation_imports
import 'package:tilawa_flutter/src/runtime/webview_adapter.dart';
// ignore: implementation_imports
import 'package:tilawa_flutter/src/runtime/native_adapter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'audio_fixture.dart';
import 'native_probe_adapter.dart';
import 'native_worker_probe.dart';
import 'hybrid_probe.dart';

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
      if (const bool.fromEnvironment('PROBE_HEAP')) {
        await native.invokeMethod<void>('webDebugging', true);
      }
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
      } else if (mode == 'resources' ||
          mode.startsWith('resources-native') ||
          mode.startsWith('mic-native')) {
        await resources(assets);
      } else if (mode == 'switch-only') {
        await switching(assets);
      } else if (mode == 'trace-switch') {
        await switching(assets, trace: true);
      } else if (mode == 'recreation-only') {
        await recreation(assets);
      } else if (mode == 'reuse-recognition') {
        await reuseRecognition(assets);
      } else if (mode == 'memory-profile') {
        await memoryProfile(assets);
      } else if (mode.startsWith('throughput-long')) {
        final pcm = await load('assets/runtime/validation_ref_002255.audio');
        session = await TilawaSession.open(
          assets: assets,
          config: const TilawaRecognitionConfig(diagnostics: true),
          adapterFactory: mode.endsWith('hybrid')
              ? const HybridProbeFactory()
              : mode.endsWith('tuned')
              ? const TilawaNativeAdapterFactory(
                  intraOpNumThreads: 2,
                  useArena: true,
                )
              : null,
        );
        await passage('throughput-long-002255', pcm, [
          [
            {'surah': 2, 'ayah': 255},
          ],
        ]);
      } else if (mode == 'parity') {
        final directory = await getExternalStorageDirectory();
        final raw = await File(
          '${directory!.path}/tilawa-profile.pcm',
        ).readAsBytes();
        final pcm = Float32List.view(
          raw.buffer,
          raw.offsetInBytes,
          raw.length ~/ 4,
        );
        for (final backend in ['webview', 'native']) {
          session = await TilawaSession.open(
            assets: assets,
            adapterFactory: backend == 'webview'
                ? const TilawaWebViewAdapterFactory()
                : null,
          );
          log('PARITY_BACKEND', {
            'backend': backend,
            'adapterId': session!.info.adapterId,
          });
          await passage('parity-$backend', pcm, [
            [
              for (var ayah = 1; ayah <= 5; ayah++)
                {'surah': 113, 'ayah': ayah},
            ],
          ]);
          await session!.dispose();
          session = null;
        }
      } else if (mode == 'prepare-pcm') {
        final pcm = await load(
          'assets/runtime/validation_multi_113_001_005.audio',
        );
        final directory = await getExternalStorageDirectory();
        if (directory == null) {
          throw StateError('No private external app directory');
        }
        final file = File('${directory.path}/tilawa-profile.pcm');
        await file.writeAsBytes(
          pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
          flush: true,
        );
        log('PCM_PREPARED', {
          'file': file.path,
          'samples': pcm.length,
          'format': 'mono16k-float32le',
        });
      } else {
        throw StateError('Unknown validation mode');
      }
      log('COMPLETE', {'mode': mode, 'stoppedByUser': stopRequested});
    } catch (error, stack) {
      log('ERROR', {
        'message': '$error',
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
        'interruption': session?.snapshot.lastResult?.interruption?.code,
      });
      debugPrint('$stack');
    } finally {
      await session?.dispose();
      if (const bool.fromEnvironment('PROBE_HEAP')) {
        await native.invokeMethod<void>('webDebugging', false);
      }
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

  Future<void> switching(
    TilawaPreparedAssets assets, {
    bool trace = false,
  }) async {
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
      adapterFactory: trace ? _MeasuredFactory(log) : null,
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
    final matchedRefs = <String>[];
    final progressRefs = <String>{};
    final progressSnapshots = <Object?>[];
    final events = session!.events.listen((event) {
      if (event is TilawaVerseMatched) {
        matches++;
        matchedRefs.add('${event.ayah}');
      }
      if (event is TilawaWordProgress) {
        progress++;
        progressRefs.add('${event.ayah}');
        progressSnapshots.add([
          '${event.ayah}',
          event.wordIndex,
          event.totalWords,
          event.matchedIndices,
        ]);
      }
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
    var maxFeedMs = 0;
    for (
      var offset = 0;
      offset < pcm.length && !stopRequested;
      offset += 7680
    ) {
      final feedClock = Stopwatch()..start();
      await session!.feed(
        Float32List.sublistView(pcm, offset, min(offset + 7680, pcm.length)),
      );
      maxFeedMs = max(maxFeedMs, feedClock.elapsedMilliseconds);
    }
    final feedMs = clock.elapsedMilliseconds;
    final flushClock = Stopwatch()..start();
    final result = await session!.stop();
    log('PASSAGE_TIMING', {
      'id': id,
      'feedMs': feedMs,
      'flushMs': flushClock.elapsedMilliseconds,
      'maxFeedMs': maxFeedMs,
      'audioMs': (pcm.length / 16).round(),
    });
    await Future<void>.delayed(Duration.zero);
    await events.cancel();
    log('PROGRESS_FINGERPRINT', {
      'id': id,
      'snapshots': progressSnapshots.length,
      'sha256': sha256
          .convert(utf8.encode(jsonEncode(progressSnapshots)))
          .toString(),
    });
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
      'matchedRefs': matchedRefs,
      'progress': progress,
      'progressRefs': progressRefs.toList(),
      'candidates': candidates.toList(),
      'diagnosticFallbackMentions': fallbackMatches,
      'diagnostics': diagnostics,
      'finalization': result.finalization.name,
      'processedSamples': result.processedSamples,
    });
  }

  Future<void> memoryProfile(TilawaPreparedAssets assets) async {
    const variant = String.fromEnvironment(
      'PROBE_MEMORY_VARIANT',
      defaultValue: 'baseline',
    );
    final options = <String, Object?>{};
    if (variant == 'url') options['loadMode'] = 'url';
    if (variant == 'basic' || variant == 'basic-no-prepack') {
      options['graphOptimizationLevel'] = 'basic';
    }
    if (variant == 'arena') options['enableCpuMemArena'] = true;
    if (variant == 'no-prepack' || variant == 'basic-no-prepack') {
      options['extra'] = {
        'session': {'disable_prepacking': '1'},
      };
    }
    final directory = await getExternalStorageDirectory();
    if (directory == null) {
      throw StateError('No private external app directory');
    }
    final raw = await File(
      '${directory.path}/tilawa-profile.pcm',
    ).readAsBytes();
    if (raw.length % 4 != 0) throw StateError('Incomplete prepared PCM');
    final pcm = Float32List.view(
      raw.buffer,
      raw.offsetInBytes,
      raw.length ~/ 4,
    );
    log('MEMORY_VARIANT', {
      'variant': variant,
      'options': options,
      'fixtureDecoder': false,
      'inputSamples': pcm.length,
    });
    await sample('profile-baseline');
    await Future<void>.delayed(const Duration(seconds: 8));
    for (var cycle = 1; cycle <= 2 && !stopRequested; cycle++) {
      await requireForeground();
      await sample('profile-$cycle-opening');
      final clock = Stopwatch()..start();
      session = await TilawaSession.open(
        assets: assets,
        adapterFactory: variant == 'hybrid'
            ? const HybridProbeFactory()
            : variant.startsWith('sdk-native')
            ? null
            : variant == 'native-worker'
            ? const NativeWorkerProbeFactory()
            : variant.startsWith('native')
            ? const NativeProbeFactory()
            : TilawaWebViewAdapterFactory(sessionOptions: options),
      );
      log('PROFILE_OPEN', {
        'cycle': cycle,
        'elapsedMs': clock.elapsedMilliseconds,
        'adapterId': session!.info.adapterId,
      });
      await sample('profile-$cycle-ready');
      await Future<void>.delayed(const Duration(seconds: 8));
      await sample('profile-$cycle-processing');
      await passage('profile-$variant-$cycle', pcm, [
        [
          for (var ayah = 1; ayah <= 5; ayah++) {'surah': 113, 'ayah': ayah},
        ],
      ]);
      await sample('profile-$cycle-steady');
      await Future<void>.delayed(const Duration(seconds: 8));
      await session!.reset();
      await sample('profile-$cycle-reset');
      await Future<void>.delayed(const Duration(seconds: 4));
      await session!.dispose();
      session = null;
      await sample('profile-$cycle-disposed');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    await Future<void>.delayed(const Duration(seconds: 20));
    await sample('profile-settled');
  }

  Future<void> reuseRecognition(TilawaPreparedAssets assets) async {
    final pcm = await load('assets/runtime/validation_multi_113_001_005.audio');
    for (var cycle = 1; cycle <= 3 && !stopRequested; cycle++) {
      await requireForeground();
      session = await TilawaSession.open(assets: assets);
      await passage('reuse-recognition-$cycle', pcm, [
        [
          for (var ayah = 1; ayah <= 5; ayah++) {'surah': 113, 'ayah': ayah},
        ],
      ]);
      await session!.dispose();
      session = null;
      // Third open exercises cache expiry, rather than only warm reuse.
      if (cycle == 2) await Future<void>.delayed(const Duration(seconds: 16));
    }
    if (stopRequested) return;
    final first = await TilawaSession.open(assets: assets);
    final second = await TilawaSession.open(assets: assets);
    try {
      await first.feed(Float32List(16000));
      await second.feed(Float32List(8000));
      final a = await first.stop();
      final b = await second.stop();
      if (a.processedSamples != 16000 ||
          b.processedSamples != 8000 ||
          a.finalization != TilawaFinalization.complete ||
          b.finalization != TilawaFinalization.complete) {
        throw StateError('Concurrent runtime sample isolation failed');
      }
      log('REUSE_CONCURRENT', {
        'firstSamples': a.processedSamples,
        'secondSamples': b.processedSamples,
        'isolated': true,
      });
    } finally {
      await first.dispose();
      await second.dispose();
    }
    await Future<void>.delayed(const Duration(seconds: 16));
    log('REUSE_EXPIRED', {'settledSeconds': 16});
  }

  Future<void> recreation(TilawaPreparedAssets assets) async {
    // No fixture decoder, microphone, or custom adapter in this mode.
    await sample('recreation-baseline');
    await Future<void>.delayed(const Duration(seconds: 5));
    for (var cycle = 1; cycle <= 3 && !stopRequested; cycle++) {
      await requireForeground();
      await sample('isolated-$cycle-before-open');
      final open = Stopwatch()..start();
      const destroy = bool.fromEnvironment('PROBE_DESTROY_WEBVIEW');
      session = await TilawaSession.open(
        assets: assets,
        adapterFactory: destroy
            ? TilawaWebViewAdapterFactory(
                disposeController: (controller) async {
                  final platform =
                      controller.platform as AndroidWebViewController;
                  await native.invokeMethod<void>(
                    'destroyWebView',
                    platform.webViewIdentifier,
                  );
                },
              )
            : null,
      );
      log('OPEN', {'cycle': cycle, 'elapsedMs': open.elapsedMilliseconds});
      await sample('isolated-$cycle-open');
      await Future<void>.delayed(const Duration(seconds: 5));
      for (var offset = 0; offset < 32000 && !stopRequested; offset += 7680) {
        await session!.feed(Float32List(min(7680, 32000 - offset)));
      }
      final result = await session!.stop();
      log('ISOLATED_STOP', {
        'cycle': cycle,
        'submittedSamples': result.submittedSamples,
        'processedSamples': result.processedSamples,
        'finalization': result.finalization.name,
        'sequence': result.engineSequence?.map((v) => '${v.ayah}').toList(),
      });
      await sample('isolated-$cycle-active');
      await Future<void>.delayed(const Duration(seconds: 5));
      final disposal = Stopwatch()..start();
      await session!.dispose();
      session = null;
      log('ISOLATED_DISPOSE', {
        'cycle': cycle,
        'elapsedMs': disposal.elapsedMilliseconds,
      });
      await sample('isolated-$cycle-disposed');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    var previous = 0;
    for (final seconds in [0, 15, 30, 60, 90]) {
      if (stopRequested) break;
      await Future<void>.delayed(Duration(seconds: seconds - previous));
      await requireForeground();
      await sample('isolated-settle-$seconds');
      previous = seconds;
    }
  }

  Future<void> resources(TilawaPreparedAssets assets) async {
    await sample('before-decode');
    final directory = await getExternalStorageDirectory();
    final raw = await File(
      '${directory!.path}/tilawa-profile.pcm',
    ).readAsBytes();
    final pcm = Float32List.view(
      raw.buffer,
      raw.offsetInBytes,
      raw.length ~/ 4,
    );
    await sample('after-decode');
    var factory = _MeasuredFactory();
    final open = Stopwatch()..start();
    session = await TilawaSession.open(assets: assets, adapterFactory: factory);
    log('OPEN', {
      'cycle': 0,
      'adapterId': session!.info.adapterId,
      'elapsedMs': open.elapsedMilliseconds,
      'adapterInitializeMs': factory.initializeMs,
    });
    await sample('first-open');
    if (!const String.fromEnvironment(
      'PROBE_VALIDATION',
    ).startsWith('mic-native')) {
      await paced(pcm, factory);
    }
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
    final sessionEvents = session!.events.listen((event) {
      if (event is TilawaSessionEnded && event.result.interruption != null) {
        log('MIC_INTERRUPTED', {
          'code': event.result.interruption!.code,
          'finalization': event.result.finalization.name,
        });
      }
    });
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
      await sessionEvents.cancel();
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
            'Opt-in validation. Recreation-only uses three silence cycles, no microphone or decoder. Resources mode starts microphone after paced input. Keep unlocked and foregrounded.',
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
  _MeasuredFactory([this.trace]);
  final void Function(String, Map<String, Object?>)? trace;
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
    final progress = <String, int>{};
    const mode = String.fromEnvironment('PROBE_VALIDATION');
    final TilawaEngineAdapterFactory backend =
        (mode.startsWith('resources-native') || mode.startsWith('mic-native'))
        ? const TilawaNativeAdapterFactory()
        : const TilawaWebViewAdapterFactory();
    final inner = await backend.create(assets, config, (event) {
      if (trace != null) {
        if (event['type'] == 'word_progress') {
          final ref = '${event['surah']}:${event['ayah']}';
          progress.update(ref, (count) => count + 1, ifAbsent: () => 1);
          if (progress[ref] == 1) trace!('RAW_FIRST_PROGRESS', event);
        } else if ([
          'debug',
          'verse_match',
          'verse_candidate',
          'final_sequence',
        ].contains(event['type'])) {
          trace!('RAW_EVENT', event);
        }
      }
      sink(event);
    });
    initializeMs = clock.elapsedMilliseconds;
    return _MeasuredAdapter(inner, timings, trace, progress);
  }
}

final class _MeasuredAdapter implements TilawaEngineAdapter {
  _MeasuredAdapter(this.inner, this.timings, this.trace, this.progress);
  final TilawaEngineAdapter inner;
  final List<int> timings;
  final void Function(String, Map<String, Object?>)? trace;
  final Map<String, int> progress;
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
  Future<TilawaEngineSnapshot> stop() async {
    final result = await inner.stop();
    trace?.call('RAW_STOP', {
      'sequence': result.sequence?.map((v) => '${v.ayah}').toList(),
      'consumedSamples': result.consumedSamples,
      'progressByRef': progress,
    });
    return result;
  }

  @override
  Future<TilawaEngineSnapshot> reset() => inner.reset();
  @override
  Future<int> describeAyah(TilawaAyahRef ayah) => inner.describeAyah(ayah);
  @override
  Future<void> dispose() => inner.dispose();
}
