import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

void main() {
  late TilawaPassageStartMonitor monitor;
  setUp(() {
    monitor = TilawaPassageStartMonitor(
      passage: const TilawaExpectedPassage(TilawaAyahRef(112, 1), ayahEnd: 4),
      sessionId: 'session',
      runId: 'run',
      attempt: 0,
    );
  });
  TilawaWordVerdict word(
    int ayah,
    int index, {
    TilawaWordVerdictState state = TilawaWordVerdictState.correct,
  }) => TilawaWordVerdict(
    position: TilawaWordRef(TilawaAyahRef(112, ayah), index),
    corpusWordIndex: ayah * 10 + index,
    state: state,
    distance: 0,
    margin: 1,
    heardRatio: 1,
    vowelErrors: 0,
    vowelMargin: 0,
  );
  TilawaWordEvidence evidence(
    int revision,
    int phonemes,
    List<TilawaWordVerdict> words, {
    String run = 'run',
    int attempt = 0,
    bool ended = false,
    bool independent = true,
  }) => TilawaWordEvidence(
    TilawaEventContext(
      sessionId: 'session',
      runId: run,
      sequence: revision,
      emittedAt: DateTime.utc(2026),
      elapsedSinceOpen: Duration.zero,
      inputPositionSamples: 100,
    ),
    revision: revision,
    attempt: attempt,
    phonemeCount: phonemes,
    audioEnded: ended,
    words: words,
    startComparison: independent
        ? const TilawaStartComparison(
            laterAyah: TilawaAyahRef(112, 2),
            expectedDistance: .8,
            laterDistance: .1,
            phonemes: 30,
          )
        : null,
  );

  test(
    'clear expected prefix supports starting point, not full correctness',
    () {
      expect(
        monitor.observe(evidence(1, 20, [word(1, 0), word(1, 1)])).status,
        TilawaPassageStartStatus.supported,
      );
    },
  );
  test(
    'starting next ayah requires new advancing evidence, not repeated snapshots',
    () {
      expect(
        monitor.observe(evidence(1, 20, [word(2, 0), word(2, 1)])).status,
        TilawaPassageStartStatus.awaitingEvidence,
      );
      expect(
        monitor.observe(evidence(2, 20, [word(2, 0), word(2, 1)])).status,
        TilawaPassageStartStatus.awaitingEvidence,
      );
      expect(
        monitor
            .observe(evidence(3, 30, [word(2, 0), word(2, 1), word(2, 2)]))
            .status,
        TilawaPassageStartStatus.possibleSkippedStart,
      );
    },
  );
  test('silence/uncertain/pending evidence never proves a skipped start', () {
    monitor.observe(evidence(1, 0, []));
    monitor.observe(
      evidence(2, 20, [
        word(2, 0, state: TilawaWordVerdictState.uncertain),
        word(2, 1),
      ]),
    );
    expect(
      monitor
          .observe(
            evidence(3, 30, [
              word(2, 0, state: TilawaWordVerdictState.pending),
              word(2, 1),
              word(2, 2),
            ]),
          )
          .status,
      TilawaPassageStartStatus.awaitingEvidence,
    );
  });
  test('old runs and retry audio cannot establish original starting point', () {
    monitor.observe(evidence(1, 20, [word(2, 0), word(2, 1)], run: 'old'));
    expect(
      monitor
          .observe(
            evidence(2, 30, [word(2, 0), word(2, 1), word(2, 2)], attempt: 1),
          )
          .status,
      TilawaPassageStartStatus.awaitingEvidence,
    );
  });
  test(
    'corrected replacement opening removes a provisional skipped-start flag',
    () {
      monitor.observe(evidence(1, 20, [word(2, 0), word(2, 1)]));
      monitor.observe(evidence(2, 30, [word(2, 0), word(2, 1), word(2, 2)]));
      expect(
        monitor.observe(evidence(3, 40, [word(1, 0), word(1, 1)])).status,
        TilawaPassageStartStatus.supported,
      );
    },
  );
  test(
    'without independent prefix evidence, uncertain opening remains unresolved',
    () {
      final opening = word(1, 0, state: TilawaWordVerdictState.uncertain);
      monitor.observe(
        evidence(1, 20, [opening, word(2, 0), word(2, 1)], independent: false),
      );
      expect(
        monitor
            .observe(
              evidence(2, 30, [
                opening,
                word(2, 0),
                word(2, 1),
                word(2, 2),
              ], independent: false),
            )
            .status,
        TilawaPassageStartStatus.awaitingEvidence,
      );
    },
  );
  test(
    'empty terminal snapshot does not erase established opening evidence',
    () {
      monitor.observe(evidence(1, 20, [word(1, 0), word(1, 1)]));
      expect(
        monitor.observe(evidence(2, 20, [], ended: true)).status,
        TilawaPassageStartStatus.supported,
      );
    },
  );
  test(
    'actual pinned engine snapshots distinguish synthetic clean/skipped openings',
    () {
      final data =
          jsonDecode(
                File(
                  Platform.environment['TILAWA_START_EVIDENCE']!,
                ).readAsStringSync(),
              )
              as Map;
      for (final name in ['clean', 'skipped']) {
        final actual = TilawaPassageStartMonitor(
          passage: const TilawaExpectedPassage(
            TilawaAyahRef(112, 1),
            ayahEnd: 4,
          ),
          sessionId: 'session',
          runId: 'run',
          attempt: 0,
        );
        var flagged = false;
        for (final raw in data[name] as List) {
          final comparison = raw['start_comparison'] as Map?;
          final words = (raw['words'] as List)
              .map(
                (w) => TilawaWordVerdict(
                  position: TilawaWordRef(
                    TilawaAyahRef(w['surah'], w['ayah']),
                    w['word'],
                  ),
                  corpusWordIndex: w['wordIndex'],
                  state: switch (w['state']) {
                    'ok' => TilawaWordVerdictState.correct,
                    'unsure' => TilawaWordVerdictState.uncertain,
                    'wrong' => TilawaWordVerdictState.wrong,
                    'skipped' => TilawaWordVerdictState.skipped,
                    _ => TilawaWordVerdictState.pending,
                  },
                  distance: (w['distance'] as num).toDouble(),
                  margin: (w['margin'] as num).toDouble(),
                  heardRatio: (w['heardRatio'] as num).toDouble(),
                  vowelErrors: w['vowelErrors'],
                  vowelMargin: (w['vowelMargin'] as num).toDouble(),
                ),
              )
              .toList();
          final state = actual.observe(
            TilawaWordEvidence(
              evidence(raw['revision'], raw['phoneme_count'], []).context,
              revision: raw['revision'],
              attempt: 0,
              phonemeCount: raw['phoneme_count'],
              audioEnded: false,
              words: words,
              startComparison: comparison == null
                  ? null
                  : TilawaStartComparison(
                      laterAyah: TilawaAyahRef(
                        comparison['surah'],
                        comparison['ayah'],
                      ),
                      expectedDistance: (comparison['expected_distance'] as num)
                          .toDouble(),
                      laterDistance: (comparison['later_distance'] as num)
                          .toDouble(),
                      phonemes: comparison['phonemes'],
                    ),
            ),
          );
          flagged |=
              state.status == TilawaPassageStartStatus.possibleSkippedStart;
        }
        expect(flagged, name == 'skipped', reason: name);
        if (name == 'clean') {
          expect(actual.assessment.status, TilawaPassageStartStatus.supported);
        } else {
          expect(actual.assessment.status, TilawaPassageStartStatus.possibleSkippedStart);
        }
      }
    },
    skip: Platform.environment['TILAWA_START_EVIDENCE'] == null,
  );
}
