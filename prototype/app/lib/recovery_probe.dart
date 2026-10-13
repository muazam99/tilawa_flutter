// Private opt-in Android recovery diagnostics. Never distributed as example code.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tilawa_flutter/microphone.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

import 'asset_probe.dart';

Future<void> runRecoveryProbe(
  TilawaPreparedAssets assets,
  AssetProbeLog log,
) async {
  const config = TilawaRecognitionConfig(
    interruptionDeadline: Duration(milliseconds: 400),
    disposalDeadline: Duration(seconds: 2),
  );
  final factory = RecoveryFactory();
  final session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: factory,
  );
  final microphone = await TilawaMicrophone.open(
    session: session,
    maxPendingChunks: 1,
  );
  final overload = Completer<void>();
  final ended = Completer<TilawaSessionResult>();
  final errors = microphone.errors.listen((error) {
    log('RECOVERY_CAPTURE_ERROR code=${error.code}');
    if (error.code == 'audioOverrun' && !overload.isCompleted) {
      overload.complete();
    }
  });
  final events = session.events.listen((event) {
    if (event is TilawaSessionEnded && !ended.isCompleted) {
      ended.complete(event.result);
    }
  });
  try {
    await microphone.start();
    await factory.adapter.entered.future.timeout(const Duration(seconds: 5));
    await overload.future.timeout(const Duration(seconds: 5));
    try {
      final result = await ended.future.timeout(const Duration(seconds: 2));
      requireAssetProbe(
        result.finalization == TilawaFinalization.incomplete &&
            result.engineSequence == null,
        'Stalled capture appeared completely finalized',
      );
      log('RECOVERY_OVERLOAD bounded=true incomplete=true');
    } on TimeoutException {
      log(
        'RECOVERY_OVERLOAD_STUCK lifecycle=${session.snapshot.state.name} '
        'capture=${microphone.state.name} deadlineMs=400 waitedMs=2000',
      );
      if (const bool.fromEnvironment('PROBE_RECOVERY_REQUIRE_FIXED')) rethrow;
    }
  } finally {
    factory.adapter.release();
    await microphone.dispose().timeout(const Duration(seconds: 5));
    await session.dispose();
    await errors.cancel();
    await events.cancel();
  }
  if (const bool.fromEnvironment('PROBE_RECOVERY_REQUIRE_FIXED')) {
    await _stalledStop(assets, config, log);
    await _captureRaces(assets, config, log);
    await _cleanupFaults(assets, config, log);
  }
  log('RECOVERY_CHECKS_COMPLETE');
}

Future<void> runNativeFocusProbe(
  TilawaPreparedAssets assets,
  AssetProbeLog log,
) async {
  const native = MethodChannel('dev.qiyam.tilawa_bridge_probe/diagnostics');
  final session = await TilawaSession.open(assets: assets);
  var mic = await TilawaMicrophone.open(session: session);
  final ended = Completer<TilawaSessionResult>();
  final events = session.events.listen((event) {
    if (event is TilawaSessionEnded && !ended.isCompleted) {
      ended.complete(event.result);
    }
  });
  try {
    await mic.start();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final snapshot = await native.invokeMapMethod<String, dynamic>('snapshot');
    log('RECOVERY_NATIVE_FORMAT recordings=${snapshot?['recordings']}');
    final granted = await native.invokeMethod<int>('takeFocus');
    requireAssetProbe(granted == 1, 'Competing native audio focus denied');
    final result = await ended.future.timeout(const Duration(seconds: 15));
    requireAssetProbe(
      result.interruption?.code == 'audioFocusLoss',
      'Focus did not interrupt capture',
    );
    await native.invokeMethod<void>('releaseFocus');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    requireAssetProbe(
      mic.state != TilawaCaptureState.capturing,
      'Focus regain restarted capture',
    );
    await mic.dispose();
    await session.reset();
    mic = await TilawaMicrophone.open(session: session);
    await mic.start();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await mic.stopCapture();
    final recovered = await session.stop();
    log(
      'RECOVERY_NATIVE_FOCUS reason=${result.interruption?.code} finalization=${result.finalization.name} automaticRestart=false recovered=${recovered.finalization.name}',
    );
  } finally {
    await native.invokeMethod<void>('releaseFocus');
    await session.dispose();
    await events.cancel();
  }
}

Future<void> _stalledStop(
  TilawaPreparedAssets assets,
  TilawaRecognitionConfig config,
  AssetProbeLog log,
) async {
  final factory = RecoveryFactory();
  final session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: factory,
  );
  final mic = await TilawaMicrophone.open(session: session);
  final ended = Completer<TilawaSessionResult>();
  final events = session.events.listen((event) {
    if (event is TilawaSessionEnded && !ended.isCompleted) {
      ended.complete(event.result);
    }
  });
  try {
    await mic.start();
    await factory.adapter.entered.future.timeout(const Duration(seconds: 5));
    await expectAssetError('operationTimeout', mic.stopCapture);
    final result = await ended.future.timeout(const Duration(seconds: 2));
    requireAssetProbe(
      result.finalization == TilawaFinalization.incomplete,
      'Stalled Stop appeared complete',
    );
    log('RECOVERY_STOP_STALLED bounded=true incomplete=true');
  } finally {
    // Dispose while feed remains stalled. Capture must not wait for that feed.
    await session.dispose();
    requireAssetProbe(
      mic.state == TilawaCaptureState.disposed,
      'Session left capture alive',
    );
    factory.adapter.release();
    await events.cancel();
  }
}

Future<void> _captureRaces(
  TilawaPreparedAssets assets,
  TilawaRecognitionConfig config,
  AssetProbeLog log,
) async {
  final factory = RecoveryFactory();
  final session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: factory,
  );
  factory.adapter.release();
  var mic = await TilawaMicrophone.open(session: session);
  try {
    for (var i = 0; i < 5; i++) {
      final start = mic.start();
      requireAssetProbe(
        identical(start, mic.start()),
        'Concurrent Start did not coalesce',
      );
      final stop = mic.stopCapture();
      requireAssetProbe(
        identical(stop, mic.stopCapture()),
        'Concurrent Stop did not coalesce',
      );
      await start;
      await stop;
      requireAssetProbe(
        mic.state == TilawaCaptureState.idle,
        'Rapid Stop left capture active',
      );
    }
    final closing = mic.dispose();
    await expectAssetError('invalidState', () async {
      await TilawaMicrophone.open(session: session);
    });
    await closing;
    mic = await TilawaMicrophone.open(session: session);
    final start = mic.start();
    start.ignore();
    final dispose = mic.dispose();
    await expectAssetError('captureInterrupted', () => start);
    await dispose;
    requireAssetProbe(
      mic.state == TilawaCaptureState.disposed,
      'Dispose during Start left capture active',
    );
    mic = await TilawaMicrophone.open(session: session);
    await mic.start();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await mic.stopCapture();
    await session.stop();
    await mic.dispose();
    await session.reset();
    mic = await TilawaMicrophone.open(session: session);
    await mic.start();
    await session.dispose();
    await expectAssetError('invalidState', () async {
      await TilawaMicrophone.open(session: session);
    });
    requireAssetProbe(
      mic.state == TilawaCaptureState.disposed,
      'Active-session disposal left helper alive',
    );
    log(
      'RECOVERY_RACES cycles=5 startStopCoalesced=true replacementGuarded=true disposeDuringStart=true resetRestart=true',
    );
  } finally {
    await mic.dispose();
    await session.dispose();
  }
}

Future<void> _cleanupFaults(
  TilawaPreparedAssets assets,
  TilawaRecognitionConfig config,
  AssetProbeLog log,
) async {
  final factory = RecoveryFactory();
  final session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: factory,
  );
  final seen = <TilawaEvent>[];
  final events = session.events.listen(seen.add);
  final feed = session.feed(Float32List(160));
  feed.ignore();
  await factory.adapter.entered.future;
  factory.adapter.sink({
    'type': '_runtime_failure',
    'message': 'Private controlled bridge loss',
  });
  factory.adapter.release();
  await expectAssetError('bridgeDisconnected', () async {
    await feed;
  });
  await expectAssetError('bridgeDisconnected', session.reset);
  factory.adapter.cleanup = Completer<void>();
  await expectAssetError('disposalFailed', session.dispose);
  final store = TilawaAssetStore(assets.installationDirectory!.parent);
  await expectAssetError('assetsInUse', () => store.delete(assets.manifest));
  factory.adapter.sink({
    'type': 'raw_transcript',
    'text': 'late',
    'confidence': 1.0,
  });
  await Future<void>.delayed(Duration.zero);
  requireAssetProbe(
    seen.whereType<TilawaTranscriptUpdated>().isEmpty,
    'Late disposed output leaked',
  );
  factory.adapter.cleanup!.complete();
  await Future<void>.delayed(Duration.zero);
  await events.cancel();
  log(
    'RECOVERY_BRIDGE injected=true feedResetRejected=true lateOutputFenced=true cleanupTimeoutLeaseHeld=true',
  );

  final failed = RecoveryFactory();
  final failedSession = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: failed,
  );
  failed.adapter.cleanupFails = true;
  await expectAssetError('disposalFailed', failedSession.dispose);
  await expectAssetError('assetsInUse', () => store.delete(assets.manifest));
  log('RECOVERY_CLEANUP_FAILURE leaseHeld=true disposed=true');
}

Future<void> runNativeBridgeProbe(
  TilawaPreparedAssets assets,
  AssetProbeLog log,
) async {
  const native = MethodChannel('dev.qiyam.tilawa_bridge_probe/diagnostics');
  await native.invokeMethod<void>('webDebugging', true);
  TilawaSession? session;
  StreamSubscription<TilawaEvent>? events;
  try {
    session = await TilawaSession.open(assets: assets);
    final seen = <TilawaEvent>[];
    events = session.events.listen(seen.add);
    log('RECOVERY_NATIVE_BRIDGE_READY injectWindowSeconds=20');
    // The operator installs the private CDP fault hook during this window.
    await Future<void>.delayed(const Duration(seconds: 20));
    await expectAssetError('bridgeDisconnected', () async {
      await session!
          .feed(Float32List(7680))
          .timeout(const Duration(seconds: 5));
    });
    await expectAssetError('bridgeDisconnected', session.reset);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    requireAssetProbe(
      seen.whereType<TilawaTranscriptUpdated>().isEmpty,
      'Real bridge late output leaked',
    );
    await session.dispose();
    await events.cancel();
    events = null;
    session = await TilawaSession.open(assets: assets);
    await session.feed(Float32List(7680));
    final result = await session.stop();
    log(
      'RECOVERY_NATIVE_BRIDGE jsFault=true pendingFeedRejected=true lateOutputFenced=true freshSession=${result.finalization.name}',
    );
  } finally {
    await session?.dispose();
    await events?.cancel();
    await native.invokeMethod<void>('webDebugging', false);
  }
}

final class RecoveryFactory implements TilawaEngineAdapterFactory {
  late RecoveryAdapter adapter;
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async => adapter = RecoveryAdapter(sink);
}

final class RecoveryAdapter implements TilawaEngineAdapter {
  RecoveryAdapter(this.sink);
  final TilawaObservationSink sink;
  final gate = Completer<void>();
  final entered = Completer<void>();
  int samples = 0;
  Completer<void>? cleanup;
  bool cleanupFails = false;
  void release() {
    if (!gate.isCompleted) gate.complete();
  }

  @override
  String get id => 'private-recovery-probe';
  @override
  String get version => '1';
  @override
  TilawaCapabilities get capabilities => TilawaCapabilities(observations: {});
  TilawaEngineSnapshot snapshot({bool finalizing = false}) =>
      TilawaEngineSnapshot(
        consumedSamples: samples,
        transcript: '',
        trackingState: TilawaTrackingState.searching,
        sequence: finalizing ? [] : null,
        score: finalizing ? 0 : null,
      );
  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    samples += pcm.length;
    return snapshot();
  }

  @override
  Future<TilawaEngineSnapshot> stop() async {
    sink({'type': 'final_sequence', 'verses': [], 'confidence': 0.0});
    return snapshot(finalizing: true);
  }

  @override
  Future<TilawaEngineSnapshot> reset() async {
    samples = 0;
    return snapshot();
  }

  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async => 1;
  @override
  Future<void> dispose() async {
    if (cleanupFails) {
      throw const TilawaException('disposalFailed', 'Private cleanup failure');
    }
    await cleanup?.future;
  }
}
