import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
import 'package:tilawa_flutter/src/capture_binding.dart';
import 'package:tilawa_flutter/src/runtime/correction_protocol.dart';

// Scripted transport checks only. No real inference/accuracy claim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TilawaPreparedAssets assets;
  late _Factory factory;
  TilawaSession? session;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'tilawa-correction-test-',
    );
    final files = <String, File>{};
    final descriptions = <TilawaAssetFile>[];
    for (final name in [
      'model.onnx',
      'corpus.json',
      'io.json',
      'NPL-1.2.txt',
    ]) {
      final bytes = name.codeUnits;
      files[name] = await File('${directory.path}/$name').writeAsBytes(bytes);
      descriptions.add(
        TilawaAssetFile(
          name: name,
          bytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
          license: 'test fixture',
        ),
      );
    }
    assets = await TilawaAssets.fromLocalFiles(
      manifest: TilawaAssetManifest(
        id: 'scripted',
        engineId: 'scripted',
        engineVersion: '1',
        upstreamCommit: 'scripted',
        segmentationId: 'scripted',
        ioSchema: 'scripted',
        files: descriptions,
      ),
      model: files['model.onnx']!,
      corpus: files['corpus.json']!,
      io: files['io.json']!,
      license: files['NPL-1.2.txt']!,
    );
    factory = _Factory();
  });
  tearDown(() async {
    await session?.dispose();
    session = null;
    await directory.delete(recursive: true); // Only this test's own fixture.
  });

  Future<TilawaSession> open({
    TilawaRecitationMode mode = TilawaRecitationMode.correction,
  }) async {
    return session = await TilawaSession.open(
      assets: assets,
      adapterFactory: factory,
      config: TilawaRecognitionConfig(mode: mode),
    );
  }

  Matcher code(String code) =>
      isA<TilawaException>().having((e) => e.code, 'code', code);

  test(
    'tracking default/fallback is preserved; correction disables fallback',
    () {
      expect(
        const TilawaRecognitionConfig().mode,
        TilawaRecitationMode.tracking,
      );
      expect(const TilawaRecognitionConfig().effectiveFallback, isTrue);
      expect(
        const TilawaRecognitionConfig(
          mode: TilawaRecitationMode.correction,
        ).effectiveFallback,
        isFalse,
      );
      expect(
        () => const TilawaRecognitionConfig(
          expectedPassage: TilawaExpectedPassage(TilawaAyahRef(112, 1)),
        ).validate(),
        throwsA(code('invalidInput')),
      );
    },
  );

  test(
    'typed error, retry, corrected and continue preserve attempt identity',
    () async {
      final sdk = await open();
      final events = <TilawaEvent>[];
      final subscription = sdk.events.listen(events.add);
      factory.adapter.raiseOnNextFeed = true;
      await sdk.feed(Float32List(16));
      expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.error);
      final run = sdk.snapshot.runId;
      await sdk.correct(TilawaCorrectionAction.retry, runId: run, attempt: 0);
      expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.retrying);
      expect(sdk.snapshot.correction.attempt, 1);
      factory.adapter.correctOnNextFeed = true;
      await sdk.feed(Float32List(16));
      expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.corrected);
      await sdk.correct(
        TilawaCorrectionAction.continueReading,
        runId: run,
        attempt: 1,
      );
      expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.idle);
      expect(
        sdk.snapshot.correction.outcome,
        TilawaCorrectionOutcome.corrected,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TilawaCorrectionChanged>().length, 4);
      await subscription.cancel();
    },
  );

  test('stale attempts/runs and invalid phase actions are nonfatal', () async {
    final sdk = await open();
    factory.adapter.raiseOnNextFeed = true;
    await sdk.feed(Float32List(16));
    final oldRun = sdk.snapshot.runId;
    await expectLater(
      sdk.correct(TilawaCorrectionAction.retry, runId: oldRun, attempt: 99),
      throwsA(code('invalidState')),
    );
    await expectLater(
      sdk.correct(
        TilawaCorrectionAction.continueReading,
        runId: oldRun,
        attempt: 0,
      ),
      throwsA(code('invalidState')),
    );
    await sdk.reset();
    await expectLater(
      sdk.correct(TilawaCorrectionAction.retry, runId: oldRun, attempt: 0),
      throwsA(code('invalidState')),
    );
    expect(sdk.snapshot.state, TilawaLifecycle.ready);
  });

  test(
    'expected passage changes only before audio, survives reset, can clear',
    () async {
      final sdk = await open();
      const passage = TilawaExpectedPassage(TilawaAyahRef(112, 1), ayahEnd: 4);
      await sdk.setExpectedPassage(passage);
      expect(sdk.snapshot.expectedPassage, same(passage));
      final run = sdk.snapshot.runId;
      await sdk.feed(Float32List(16));
      await expectLater(
        sdk.setExpectedPassage(null),
        throwsA(code('invalidState')),
      );
      await sdk.reset();
      expect(sdk.snapshot.runId, isNot(run));
      expect(sdk.snapshot.expectedPassage, same(passage));
      expect(sdk.snapshot.correction.issue, isNull);
      await sdk.setExpectedPassage(null);
      expect(sdk.snapshot.expectedPassage, isNull);
    },
  );

  test(
    'invalid corpus passage is rejected without quarantining runtime',
    () async {
      final sdk = await open();
      await expectLater(
        sdk.setExpectedPassage(
          const TilawaExpectedPassage(TilawaAyahRef(112, 9)),
        ),
        throwsA(code('invalidInput')),
      );
      await sdk.feed(Float32List(16));
      expect(sdk.snapshot.state, TilawaLifecycle.accepting);
    },
  );

  test('paused audio is reported, not replayed into retry', () async {
    final sdk = await open();
    final events = <TilawaEvent>[];
    final subscription = sdk.events.listen(events.add);
    factory.adapter.raiseOnNextFeed = true;
    await sdk.feed(Float32List(16));
    await sdk.feed(Float32List(32));
    await sdk.correct(
      TilawaCorrectionAction.retry,
      runId: sdk.snapshot.runId,
      attempt: 0,
    );
    expect(factory.adapter.analyzed, 16);
    await sdk.feed(Float32List(8));
    expect(factory.adapter.analyzed, 24);
    expect(sdk.snapshot.processedSamples, 56);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<TilawaAudioDiscarded>().single.samples, 32);
    await subscription.cancel();
  });

  test(
    'pending correction control blocks new audio and duplicate controls',
    () async {
      final sdk = await open();
      factory.adapter.raiseOnNextFeed = true;
      await sdk.feed(Float32List(16));
      factory.adapter.controlGate = Completer<void>();
      final action = sdk.correct(
        TilawaCorrectionAction.retry,
        runId: sdk.snapshot.runId,
        attempt: 0,
      );
      expect(sdk.snapshot.controlPending, isTrue);
      await expectLater(
        sdk.feed(Float32List(16)),
        throwsA(code('invalidState')),
      );
      await expectLater(
        sdk.correct(
          TilawaCorrectionAction.retry,
          runId: sdk.snapshot.runId,
          attempt: 0,
        ),
        throwsA(code('invalidState')),
      );
      factory.adapter.controlGate!.complete();
      await action;
      expect(sdk.snapshot.controlPending, isFalse);
    },
  );

  test(
    'capture attachment blocks correction controls until detached',
    () async {
      final sdk = await open();
      captureBindings[sdk] = () async {};
      await expectLater(
        sdk.setExpectedPassage(null),
        throwsA(code('invalidState')),
      );
      factory.adapter.raiseOnNextFeed = true;
      await sdk.feed(Float32List(16));
      await expectLater(
        sdk.correct(
          TilawaCorrectionAction.retry,
          runId: sdk.snapshot.runId,
          attempt: 0,
        ),
        throwsA(code('invalidState')),
      );
      captureBindings[sdk] = null;
      await sdk.correct(
        TilawaCorrectionAction.retry,
        runId: sdk.snapshot.runId,
        attempt: 0,
      );
      expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.retrying);
    },
  );

  test(
    'accepted paused feed drains before retry, without stale audio replay',
    () async {
      final sdk = await open();
      factory.adapter.raiseOnNextFeed = true;
      await sdk.feed(Float32List(16));
      factory.adapter.feedGate = Completer<void>();
      final queuedFeed = sdk.feed(Float32List(32));
      final action = sdk.correct(
        TilawaCorrectionAction.retry,
        runId: sdk.snapshot.runId,
        attempt: 0,
      );
      expect(sdk.snapshot.controlPending, isTrue);
      factory.adapter.feedGate!.complete();
      await queuedFeed;
      await action;
      expect(sdk.snapshot.processedSamples, 48);
      expect(factory.adapter.analyzed, 16);
      expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.retrying);
    },
  );

  test('Stop during an open issue finalizes once and is terminal', () async {
    final sdk = await open();
    factory.adapter.raiseOnNextFeed = true;
    await sdk.feed(Float32List(16));
    final result = await sdk.stop();
    expect(result.finalization, TilawaFinalization.complete);
    expect(await sdk.stop(), same(result));
    expect(factory.adapter.stops, 1);
    await expectLater(
      sdk.correct(
        TilawaCorrectionAction.retry,
        runId: sdk.snapshot.runId,
        attempt: sdk.snapshot.correction.attempt,
      ),
      throwsA(code('invalidState')),
    );
  });

  test(
    'malformed correction references discard the entire event batch',
    () async {
      final sdk = await open();
      final events = <TilawaEvent>[];
      final subscription = sdk.events.listen(events.add);
      factory.adapter.invalidWord = true;
      factory.adapter.raiseOnNextFeed = true;
      await expectLater(
        sdk.feed(Float32List(16)),
        throwsA(code('invalidEngineOutput')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TilawaCorrectionChanged>(), isEmpty);
      expect(sdk.snapshot.state, TilawaLifecycle.failed);
      await subscription.cancel();
    },
  );

  test('notes are typed and nonblocking', () async {
    final sdk = await open();
    final events = <TilawaEvent>[];
    final subscription = sdk.events.listen(events.add);
    factory.adapter.noteOnNextFeed = true;
    await sdk.feed(Float32List(16));
    await Future<void>.delayed(Duration.zero);
    expect(
      events.whereType<TilawaCorrectionNote>().single.issue.kind,
      TilawaCorrectionKind.possibleRepetition,
    );
    expect(sdk.snapshot.correction.phase, TilawaCorrectionPhase.idle);
    await subscription.cancel();
  });

  test('word evidence parses as immutable replacement snapshots', () async {
    final sdk = await open();
    final events = <TilawaEvent>[];
    final subscription = sdk.events.listen(events.add);
    factory.adapter.evidenceOnFeed = true;
    await sdk.feed(Float32List(16));
    await sdk.feed(Float32List(16));
    await Future<void>.delayed(Duration.zero);
    final evidence = events.whereType<TilawaWordEvidence>().toList();
    expect(evidence.length, 2);
    expect(evidence[0].words.single.state, TilawaWordVerdictState.uncertain);
    expect(evidence[1].words.single.state, TilawaWordVerdictState.correct);
    expect(evidence[1].revision, 2);
    expect(() => evidence[0].words.clear(), throwsUnsupportedError);
    await subscription.cancel();
  });

  test(
    'duplicate evidence revision fails without publishing the bad batch',
    () async {
      final sdk = await open();
      factory.adapter.evidenceOnFeed = true;
      await sdk.feed(Float32List(16));
      factory.adapter.evidenceRevision = 0;
      await expectLater(
        sdk.feed(Float32List(16)),
        throwsA(code('invalidEngineOutput')),
      );
      expect(sdk.snapshot.state, TilawaLifecycle.failed);
    },
  );

  test('protocol rejects unknown kinds and missing issue for error state', () {
    expect(
      () => parseCorrectionState({'phase': 'error', 'attempt': 0}),
      throwsA(code('invalidEngineOutput')),
    );
    expect(
      () => parseCorrectionIssue({..._issue, 'kind': 'certainly_wrong'}),
      throwsA(code('invalidEngineOutput')),
    );
  });
}

const _issue = <String, Object?>{
  'surah': 112,
  'ayah': 1,
  'word': 1,
  'wordIndex': 10,
  'kind': 'possible_substitution',
};

class _Factory implements TilawaEngineAdapterFactory {
  late _Adapter adapter;
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async => adapter = _Adapter(sink);
}

class _Adapter implements TilawaEngineAdapter, TilawaCorrectionAdapter {
  _Adapter(this.sink);
  final TilawaObservationSink sink;
  int samples = 0, analyzed = 0, stops = 0;
  bool raiseOnNextFeed = false,
      correctOnNextFeed = false,
      invalidWord = false,
      noteOnNextFeed = false;
  Completer<void>? controlGate;
  Completer<void>? feedGate;
  bool evidenceOnFeed = false;
  int evidenceRevision = 0;
  Map<String, Object?> state = {
    'phase': 'idle',
    'issue': null,
    'resume': null,
    'attempt': 0,
    'outcome': null,
  };
  List<TilawaSequenceVerse>? sequence;
  @override
  String get id => 'scripted';
  @override
  String get version => '1';
  @override
  TilawaCapabilities get capabilities => TilawaCapabilities(
    observations: {'correction', 'correction_note'},
    correction: true,
  );
  TilawaEngineSnapshot snap() => TilawaEngineSnapshot(
    consumedSamples: samples,
    trackingState: TilawaTrackingState.tracking,
    transcript: '',
    correction: parseCorrectionState(state),
    sequence: sequence,
    score: sequence == null ? null : 0,
  );
  void emitState() => sink({
    'type': 'correction',
    'state': state,
    'totalWords': state['issue'] == null ? 0 : 4,
  });
  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async {
    await feedGate?.future;
    if (state['phase'] == 'error' || state['phase'] == 'corrected') {
      sink({
        'type': 'audio_discarded',
        'samples': pcm.length,
        'reason': 'correction_awaiting_action',
      });
    } else {
      analyzed += pcm.length;
      if (raiseOnNextFeed) {
        raiseOnNextFeed = false;
        state = {
          ...state,
          'phase': 'error',
          'issue': {..._issue, if (invalidWord) 'word': 99},
          'resume': {'surah': 112, 'ayah': 1, 'word': 2},
        };
        emitState();
      } else if (correctOnNextFeed) {
        correctOnNextFeed = false;
        state = {...state, 'phase': 'corrected', 'outcome': 'corrected'};
        emitState();
      }
      if (noteOnNextFeed) {
        noteOnNextFeed = false;
        sink({
          'type': 'correction_note',
          'issue': {..._issue, 'kind': 'possible_repetition'},
        });
      }
    }
    samples += pcm.length;
    if (evidenceOnFeed) {
      sink({
        'type': 'word_evidence',
        'revision': ++evidenceRevision,
        'attempt': state['attempt'],
        'phoneme_count': evidenceRevision * 20,
        'audio_ended': false,
        'words': [
          {
            'surah': 112,
            'ayah': 1,
            'word': 0,
            'wordIndex': 10,
            'state': evidenceRevision == 1 ? 'unsure' : 'ok',
            'distance': 0.1,
            'heardRatio': 1,
            'margin': 1,
            'vowelErrors': 0,
            'vowelMargin': 0,
          },
        ],
      });
    }
    return snap();
  }

  @override
  Future<TilawaEngineSnapshot> correct(TilawaCorrectionAction action) async {
    await controlGate?.future;
    final retry = action == TilawaCorrectionAction.retry;
    final stopRetry = action == TilawaCorrectionAction.stopRetry;
    state = {
      ...state,
      'phase': retry
          ? 'retrying'
          : stopRetry
          ? 'error'
          : 'idle',
      'attempt': (state['attempt'] as int) + 1,
      'outcome': retry || stopRetry
          ? null
          : action == TilawaCorrectionAction.continueReading
          ? 'corrected'
          : 'deferred',
    };
    emitState();
    return snap();
  }

  @override
  Future<TilawaEngineSnapshot> reset() async {
    state = {
      'phase': 'idle',
      'issue': null,
      'resume': null,
      'attempt': (state['attempt'] as int) + 1,
      'outcome': null,
    };
    samples = 0;
    sequence = null;
    return snap();
  }

  @override
  Future<TilawaEngineSnapshot> setExpectedPassage(
    TilawaExpectedPassage? passage,
  ) async => snap();
  @override
  Future<TilawaEngineSnapshot> stop() async {
    stops++;
    if (state['phase'] != 'idle') await correct(TilawaCorrectionAction.close);
    sequence = [];
    sink({'type': 'final_sequence', 'verses': [], 'confidence': 0});
    return snap();
  }

  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async =>
      ayah.surah == 112 && ayah.ayah >= 1 && ayah.ayah <= 4 ? 4 : 0;
  @override
  Future<void> dispose() async {}
}
