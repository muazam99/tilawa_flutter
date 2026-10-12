// Private Phase 3 control diagnostics using the public adapter-factory seam.
// These isolate facade behavior; they do not claim to preempt native inference.
import 'dart:async';
import 'dart:typed_data';

import 'package:tilawa_flutter/tilawa_flutter.dart';

import 'asset_probe.dart';

Future<void> runControlProbe(
  TilawaPreparedAssets assets,
  AssetProbeLog log,
) async {
  const config = TilawaRecognitionConfig(
    interruptionDeadline: Duration(milliseconds: 100),
    disposalDeadline: Duration(milliseconds: 100),
  );
  final factory = _ControlFactory();
  var session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: factory,
  );
  try {
    await expectAssetError('invalidAudio', () async {
      await session.feed(Float32List.fromList([double.nan]));
    });
    final input = Float32List(16000)..[0] = 0.25;
    final first = session.feed(input);
    input[0] = 0.75;
    final second = session.feed(Float32List(16000));
    await expectAssetError('audioOverrun', () async {
      await session.feed(Float32List(1));
    });
    requireAssetProbe(
      session.snapshot.submittedSamples == 32000,
      'Rejected input was counted',
    );
    final stop = session.stop();
    final again = session.stop();
    requireAssetProbe(
      identical(stop, again),
      'Competing stop Futures diverged',
    );
    await expectAssetError('invalidState', () async {
      await session.feed(Float32List(1));
    });
    factory.adapter.gate.complete();
    await Future.wait([first, second]);
    final result = await stop;
    requireAssetProbe(
      result.processedSamples == 32000 && factory.adapter.firstSample == 0.25,
      'Admission copy/drain failed',
    );
    await session.reset();
    requireAssetProbe(
      session.snapshot.state == TilawaLifecycle.ready &&
          session.snapshot.processedSamples == 0,
      'Reset did not clear run',
    );
    log(
      'CONTROL_OVERLOAD rejectedNotCounted=true copied=true drain=32000 canonicalStop=true',
    );
  } finally {
    await session.dispose();
  }

  final timeoutFactory = _ControlFactory();
  session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: timeoutFactory,
  );
  final observations = <TilawaEvent>[];
  final events = session.events.listen(observations.add);
  try {
    final stalled = session.feed(Float32List(160));
    stalled.ignore();
    await timeoutFactory.adapter.entered.future;
    final result = await session.interrupt(const TilawaInterruption('probe'));
    requireAssetProbe(
      result.finalization == TilawaFinalization.incomplete &&
          result.engineSequence == null &&
          result.processedSamples == 0,
      'Timed-out interruption appeared complete',
    );
    requireAssetProbe(
      identical(result, await session.stop()),
      'Timeout terminal identity changed',
    );
    await expectAssetError('operationTimeout', () => session.reset());
    timeoutFactory.adapter.emitLate = true;
    timeoutFactory.adapter.gate.complete();
    await expectAssetError('operationTimeout', () async {
      await stalled;
    });
    await Future<void>.delayed(Duration.zero);
    requireAssetProbe(
      observations.whereType<TilawaTranscriptUpdated>().isEmpty &&
          observations.whereType<TilawaSessionEnded>().length == 1,
      'Late output escaped quarantine or terminal event repeated',
    );
    log(
      'CONTROL_INTERRUPT_TIMEOUT incomplete=true resetRejected=true lateOutputFenced=true ended=1',
    );
  } finally {
    await session.dispose();
    await events.cancel();
  }

  final raceFactory = _ControlFactory();
  session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: raceFactory,
  );
  try {
    final feed = session.feed(Float32List(160));
    final stop = session.stop();
    final reset = session.reset();
    await expectAssetError('invalidState', () async {
      await session.stop();
    });
    await expectAssetError('invalidState', () async {
      await session.feed(Float32List(1));
    });
    raceFactory.adapter.gate.complete();
    await feed;
    await stop;
    await reset;
    requireAssetProbe(
      session.snapshot.state == TilawaLifecycle.ready &&
          session.snapshot.submittedSamples == 0,
      'Queued stop/reset race failed',
    );
    log('CONTROL_STOP_RESET queued=true newInputRejected=true ready=true');
  } finally {
    await session.dispose();
  }

  final disposeFactory = _ControlFactory();
  session = await TilawaSession.open(
    assets: assets,
    config: config,
    adapterFactory: disposeFactory,
  );
  final stalled = session.feed(Float32List(160));
  stalled.ignore();
  await disposeFactory.adapter.entered.future;
  final closing = session.dispose();
  requireAssetProbe(
    identical(closing, session.dispose()),
    'Repeated disposal Futures diverged',
  );
  await closing;
  disposeFactory.adapter.gate.complete();
  await expectAssetError('disposed', () async {
    await stalled;
  });
  requireAssetProbe(
    session.snapshot.state == TilawaLifecycle.disposed &&
        disposeFactory.adapter.disposals == 1,
    'Disposal failed to fence runtime',
  );
  log(
    'CONTROL_DISPOSE_STALLED bounded=true adapterDisposedOnce=true lateFeedRejected=true',
  );
  log('CONTROL_CHECKS_COMPLETE');
}

final class _ControlFactory implements TilawaEngineAdapterFactory {
  late _ControlAdapter adapter;
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async => adapter = _ControlAdapter(sink);
}

final class _ControlAdapter implements TilawaEngineAdapter {
  _ControlAdapter(this.sink);
  final TilawaObservationSink sink;
  final gate = Completer<void>();
  final entered = Completer<void>();
  int samples = 0, disposals = 0;
  double? firstSample;
  bool emitLate = false;
  @override
  String get id => 'private-control-probe';
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
    firstSample ??= pcm.first;
    samples += pcm.length;
    if (emitLate) {
      sink({'type': 'raw_transcript', 'text': 'late', 'confidence': 1.0});
    }
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
    disposals++;
  }
}
