// Private Phase 4 diagnostics. Scripted observations isolate facade semantics;
// real engine repetitions are measured separately by tracking_probe.dart.
import 'dart:async';
import 'dart:typed_data';

import 'package:tilawa_flutter/tilawa_flutter.dart';

import 'asset_probe.dart';
import 'metadata_fixture.dart';
import 'tracking_presentation.dart';

Future<void> runTrackingContractProbe(
  TilawaPreparedAssets assets,
  FixtureMetadata fixture,
  AssetProbeLog log,
) async {
  final resolver = _MutableResolver(fixture);
  final factory = _ScriptFactory(fixture);
  final session = await TilawaSession.open(
    assets: assets,
    metadataResolver: resolver,
    adapterFactory: factory,
    config: const TilawaRecognitionConfig(diagnostics: true),
  );
  final events = <TilawaEvent>[];
  final view = TrackingPresentation();
  final subscription = session.events.listen((event) {
    events.add(event);
    view.accept(event);
  });
  try {
    const ayah = TilawaAyahRef(113, 1);
    final valid = await session.resolveMetadata(ayah);
    requireAssetProbe(
      valid!.words.length == 4 &&
          valid.pages.single == 604 &&
          valid.juz.single == 30,
      'Fixture mapping failed',
    );
    for (final mode in ['oneMany', 'ayahOnly', 'missing']) {
      resolver.mode = mode;
      final mapping = await session.resolveMetadata(ayah);
      requireAssetProbe(
        mode == 'missing' ? mapping == null : mapping != null,
        'Optional mapping mode $mode failed',
      );
    }
    final mismatchModes = [
      'bindingChange',
      'hash',
      'segmentation',
      'resultVersion',
      'resultEdition',
      'ayah',
      'count',
      'missingIndex',
      'duplicateIndex',
      'negativeIndex',
      'extraIndex',
      'emptyMapping',
      'emptyId',
      'duplicateId',
      'page',
      'juz',
      'ayahOnlyWithWords',
    ];
    for (final mode in mismatchModes) {
      resolver.mode = mode;
      await expectAssetError('metadataMismatch', () async {
        await session.resolveMetadata(ayah);
      });
    }
    resolver.mode = 'throws';
    await expectAssetError('metadataResolutionFailed', () async {
      await session.resolveMetadata(ayah);
    });
    resolver.mode = 'valid';
    await Future<void>.delayed(Duration.zero);
    requireAssetProbe(
      events.whereType<TilawaWarning>().length == mismatchModes.length + 1 &&
          session.snapshot.state == TilawaLifecycle.ready,
      'Mapping errors were not nonfatal one-warning observations',
    );
    log(
      'TRACK_METADATA valid=true oneToManyManyToOne=true ayahOnly=true missing=true '
      'mismatches=${mismatchModes.length} resolverFailure=true nonfatal=true',
    );

    // Multiple metadata requests must not attach an old result to a new run.
    for (var index = 0; index < 5; index++) {
      await session.feed(Float32List(1));
      await Future<void>.delayed(Duration.zero);
      if (index == 2) {
        requireAssetProbe(
          view.progress!.matchedIndices.join(',') == '1',
          'Consumer unioned a revised snapshot',
        );
      }
      if (index == 3) {
        requireAssetProbe(
          view.lostDiagnostic && view.tracking == TilawaTrackingState.tracking,
          'Lost diagnostic was fabricated into a sampled state transition',
        );
      }
    }
    final progress = events.whereType<TilawaWordProgress>().toList();
    requireAssetProbe(
      progress.length == 3 &&
          progress[0].matchedIndices.join(',') == '0,1' &&
          progress[1].matchedIndices.join(',') == '0,1' &&
          progress[2].matchedIndices.join(',') == '1',
      'Repeated/revised snapshots lost',
    );
    final candidates = events.whereType<TilawaVerseCandidates>().single;
    requireAssetProbe(
      candidates.candidates.single.rank == 0 &&
          candidates.candidates.single.score == 1.75,
      'Candidate fields were clamped',
    );
    requireAssetProbe(
      events.whereType<TilawaVerseMatched>().length == 2 &&
          events.whereType<TilawaVerseMatched>().every(
            (event) => event.score == 2.5 && event.provenance == 'notProvided',
          ),
      'Facade deduplicated observations or invented provenance',
    );
    final unknown = events.whereType<TilawaUnknownObservation>().single;
    requireAssetProbe(
      (unknown.payload['nested'] as Map)['values'].toString() == '[1, 2]',
      'Unknown observation was not copied deeply',
    );
    var immutable = false;
    try {
      progress.first.matchedIndices.add(3);
    } on UnsupportedError {
      immutable = true;
    }
    requireAssetProbe(immutable, 'Progress list was mutable');
    requireAssetProbe(
      view.transcript == 'replacement',
      'Transcript was appended',
    );
    final result = await session.stop();
    await Future<void>.delayed(Duration.zero);
    final finalIndex = events.indexWhere(
      (event) => event is TilawaFinalSequenceObserved,
    );
    final transcriptIndex = events.lastIndexWhere(
      (event) => event is TilawaTranscriptUpdated,
    );
    final ended = events.whereType<TilawaSessionEnded>().single;
    requireAssetProbe(
      finalIndex < transcriptIndex &&
          events.indexOf(ended) > transcriptIndex &&
          identical(result, ended.result) &&
          result.sequenceScore == 2.5 &&
          result.engineSequence!.single.score == 2.5,
      'Terminal ordering/identity/finite engine scores changed',
    );
    log(
      'TRACK_EVENTS repeatedSnapshots=true revisionReplace=true lostDiagnosticOnly=true '
      'duplicateObservationsPreserved=true immutable=true scoresUnclamped=true finalOrder=true',
    );

    final oldRun = view.runId!;
    final generation = view.metadataGeneration;
    resolver.mode = 'delayed';
    final delayed = session.resolveMetadata(ayah);
    await resolver.entered.future;
    await session.reset();
    await Future<void>.delayed(Duration.zero);
    resolver.release.complete();
    final stale = await delayed;
    requireAssetProbe(
      !view.applyMetadata(
            stale,
            requestedRun: oldRun,
            generation: generation,
            requestedAyah: ayah,
          ) &&
          view.progress == null &&
          view.transcript.isEmpty &&
          view.result == null,
      'Stale mapping entered a reset run',
    );
    requireAssetProbe(
      events.every(
            (event) => event.context.sessionId == session.snapshot.sessionId,
          ) &&
          List.generate(progress.length, (index) => index).every(
            (index) =>
                progress[index].context.inputPositionSamples == index + 1,
          ),
      'Session identity or operation-level sample position changed',
    );
  } finally {
    await session.dispose();
    await subscription.cancel();
  }
  // The entire stream is session-wide ordered, including warnings and reset.
  requireAssetProbe(
    List.generate(events.length, (index) => index).every(
      (index) =>
          index == 0 ||
          events[index].context.sequence > events[index - 1].context.sequence,
    ),
    'Event sequence was not strictly increasing',
  );
  log('TRACK_RESET staleMappingRejected=true sequenceMonotonic=true');

  final invalidFactory = _ScriptFactory(fixture, malformed: true);
  final invalid = await TilawaSession.open(
    assets: assets,
    adapterFactory: invalidFactory,
  );
  final rejected = <TilawaEvent>[];
  final badEvents = invalid.events.listen(rejected.add);
  try {
    await expectAssetError('invalidEngineOutput', () async {
      await invalid.feed(Float32List(1));
    });
    await Future<void>.delayed(Duration.zero);
    requireAssetProbe(
      rejected.whereType<TilawaVerseCandidates>().isEmpty &&
          rejected.whereType<TilawaWordProgress>().isEmpty &&
          rejected.whereType<TilawaFailure>().length == 1 &&
          invalid.snapshot.processedSamples == 0,
      'Invalid batch leaked partial observations',
    );
    log(
      'TRACK_INVALID_BATCH rejected=true noPartialObservation=true processed=0',
    );
  } finally {
    await invalid.dispose();
    await badEvents.cancel();
  }
  log('TRACK_CONTRACT_COMPLETE');
}

final class _MutableResolver implements TilawaMetadataResolver {
  _MutableResolver(this.fixture);
  final FixtureMetadata fixture;
  String mode = 'valid';
  final entered = Completer<void>(), release = Completer<void>();
  TilawaMetadataDescriptor identity({
    String? version,
    String? edition,
    String? hash,
    String? segmentation,
  }) => TilawaMetadataDescriptor(
    version: version ?? fixture.descriptor.version,
    edition: edition ?? fixture.descriptor.edition,
    corpusSha256: hash ?? fixture.descriptor.corpusSha256,
    segmentationId: segmentation ?? fixture.descriptor.segmentationId,
  );
  @override
  TilawaMetadataDescriptor get descriptor => mode == 'bindingChange'
      ? identity(version: 'switched-v2')
      : fixture.descriptor;
  @override
  Future<TilawaAyahMetadata?> resolveAyah(TilawaAyahRef ayah) async {
    if (mode == 'throws') throw StateError('Private resolver failure');
    if (mode == 'missing') return null;
    if (mode == 'delayed') {
      entered.complete();
      await release.future;
    }
    final base = fixture.ayahs[ayah]!;
    final words = base.words.toList();
    switch (mode) {
      case 'missingIndex':
        words.removeLast();
      case 'duplicateIndex':
        words[1] = words[0];
      case 'negativeIndex':
        words[0] = TilawaWordMetadata(-1, displayWordIds: ['a']);
      case 'extraIndex':
        words[0] = TilawaWordMetadata(
          base.recognitionWordCount,
          displayWordIds: ['a'],
        );
      case 'emptyMapping':
        words[0] = TilawaWordMetadata(0);
      case 'emptyId':
        words[0] = TilawaWordMetadata(0, displayWordIds: [' ']);
      case 'duplicateId':
        words[0] = TilawaWordMetadata(0, displayWordIds: ['a', 'a']);
      case 'page':
        words[0] = TilawaWordMetadata(0, pages: [0]);
      case 'juz':
        words[0] = TilawaWordMetadata(0, juz: [0]);
      case 'oneMany':
        words[0] = TilawaWordMetadata(0, displayWordIds: ['a', 'b']);
        words[1] = TilawaWordMetadata(1, displayWordIds: ['b']);
    }
    return TilawaAyahMetadata(
      ayah: mode == 'ayah' ? const TilawaAyahRef(113, 2) : ayah,
      descriptor: identity(
        version: mode == 'resultVersion' ? 'other' : null,
        edition: mode == 'resultEdition' ? 'other' : null,
        hash: mode == 'hash' ? 'wrong' : null,
        segmentation: mode == 'segmentation' ? 'wrong' : null,
      ),
      recognitionWordCount:
          base.recognitionWordCount + (mode == 'count' ? 1 : 0),
      ayahOnly: mode == 'ayahOnly' || mode == 'ayahOnlyWithWords',
      words: mode == 'ayahOnly' ? [] : words,
      text: base.text,
      pages: base.pages,
      juz: base.juz,
    );
  }
}

final class _ScriptFactory implements TilawaEngineAdapterFactory {
  _ScriptFactory(this.fixture, {this.malformed = false});
  final FixtureMetadata fixture;
  final bool malformed;
  @override
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink sink,
  ) async => _ScriptAdapter(fixture, sink, malformed);
}

final class _ScriptAdapter implements TilawaEngineAdapter {
  _ScriptAdapter(this.fixture, this.sink, this.malformed);
  final FixtureMetadata fixture;
  final TilawaObservationSink sink;
  final bool malformed;
  int samples = 0, step = 0;
  String transcript = '';
  @override
  String get id => 'private-tracking-script';
  @override
  String get version => '1';
  @override
  TilawaCapabilities get capabilities => TilawaCapabilities(observations: {});
  TilawaEngineSnapshot snapshot({bool finalizing = false}) =>
      TilawaEngineSnapshot(
        consumedSamples: samples,
        transcript: transcript,
        trackingState: TilawaTrackingState.tracking,
        sequence: finalizing
            ? [const TilawaSequenceVerse(TilawaAyahRef(113, 1), 2.5)]
            : null,
        score: finalizing ? 2.5 : null,
      );
  void progress(int index, List<int> matched) => sink({
    'type': 'word_progress',
    'surah': 113,
    'ayah': 1,
    'word_index': index,
    'total_words': 4,
    'matched_indices': matched,
  });
  void raw() =>
      sink({'type': 'raw_transcript', 'text': transcript, 'confidence': 1.0});
  @override
  Future<TilawaEngineSnapshot> feed(Float32List pcm) async {
    switch (step++) {
      case 0:
        sink({
          'type': 'verse_candidate',
          'candidates': [
            {
              'surah': 113,
              'ayah': 1,
              'confidence': 1.75,
              'rank': 0,
              'source': 'private-script',
            },
          ],
          'stable': false,
          'final_flush': false,
        });
        final matched = [0, 1];
        progress(1, malformed ? [4] : matched);
        matched.clear();
        final nested = [1, 2];
        sink({
          'type': 'private_future_kind',
          'nested': {'values': nested},
        });
        nested.clear();
        transcript = 'initial';
        raw();
      case 1:
        progress(1, [0, 1]);
      case 2:
        progress(1, [1]);
        transcript = 'replacement';
        raw();
      case 3:
        sink({
          'type': 'debug',
          'event': 'lost',
          'at': 0,
          'data': {'type': 'lost'},
        });
      case 4:
        for (var index = 0; index < 2; index++) {
          sink({
            'type': 'verse_match',
            'surah': 113,
            'ayah': 1,
            'confidence': 2.5,
            'verse_text': '',
            'surah_name': '',
            'surrounding_verses': [],
          });
        }
    }
    samples += pcm.length;
    return snapshot();
  }

  @override
  Future<TilawaEngineSnapshot> stop() async {
    sink({
      'type': 'final_sequence',
      'verses': [
        {'surah': 113, 'ayah': 1, 'confidence': 2.5},
      ],
      'confidence': 2.5,
    });
    raw();
    return snapshot(finalizing: true);
  }

  @override
  Future<TilawaEngineSnapshot> reset() async {
    samples = step = 0;
    transcript = '';
    return snapshot();
  }

  @override
  Future<int> describeAyah(TilawaAyahRef ayah) async =>
      fixture.ayahs[ayah]!.recognitionWordCount;
  @override
  Future<void> dispose() async {}
}
