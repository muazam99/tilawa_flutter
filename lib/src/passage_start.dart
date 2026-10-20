import 'models.dart';

enum TilawaPassageStartStatus {
  awaitingEvidence,
  supported,
  possibleSkippedStart,
}

/// An experimental starting-point assessment, not a correctness certificate.
/// It uses full acoustic alignment verdicts, never matchedIndices/cursor motion.
final class TilawaPassageStartAssessment {
  const TilawaPassageStartAssessment(this.status, {this.detected});
  final TilawaPassageStartStatus status;
  final TilawaWordRef? detected;
}

/// One reset-delimited, original reading attempt. Discard this monitor on reset.
/// Later retries/continues are deliberately not retroactive starting evidence.
final class TilawaPassageStartMonitor {
  TilawaPassageStartMonitor({
    required this.passage,
    required this.sessionId,
    required this.runId,
    required this.attempt,
  });
  final TilawaExpectedPassage passage;
  final String sessionId, runId;
  final int attempt;
  int _revision = 0;
  int? _candidateIndex;
  int _candidateWords = 0, _candidatePhonemes = 0;
  TilawaPassageStartAssessment _assessment = const TilawaPassageStartAssessment(
    TilawaPassageStartStatus.awaitingEvidence,
  );
  TilawaPassageStartAssessment get assessment => _assessment;

  // Same clear-word bounds as the pinned upstream correction controller. These
  // are contextual evidence gates, not calibrated accuracy probabilities.
  bool _clear(TilawaWordVerdict word) =>
      word.state == TilawaWordVerdictState.correct &&
      word.distance.isFinite &&
      word.distance <= 0.15 &&
      word.margin.isFinite &&
      word.margin >= 0.55 &&
      word.heardRatio.isFinite &&
      word.heardRatio >= 0.75 &&
      word.heardRatio <= 1.3;

  TilawaPassageStartAssessment observe(TilawaWordEvidence evidence) {
    if (evidence.context.sessionId != sessionId ||
        evidence.context.runId != runId ||
        evidence.attempt != attempt ||
        evidence.revision <= _revision) {
      return _assessment;
    }
    _revision = evidence.revision;
    if (evidence.words.isEmpty ||
        (_assessment.status == TilawaPassageStartStatus.supported &&
            evidence.words.every(
              (word) => word.position.ayah != passage.start,
            ))) {
      return _assessment;
    }
    final clear = evidence.words.where(_clear).toList()
      ..sort((a, b) => a.corpusWordIndex.compareTo(b.corpusWordIndex));
    final opening = clear
        .where(
          (word) =>
              word.position.ayah == passage.start &&
              word.position.indexInAyah == 0,
        )
        .firstOrNull;
    if (opening != null &&
        clear.any(
          (word) => word.corpusWordIndex == opening.corpusWordIndex + 1,
        )) {
      _candidateIndex = null;
      return _assessment = TilawaPassageStartAssessment(
        TilawaPassageStartStatus.supported,
        detected: opening.position,
      );
    }
    // Forced alignment may lend later audio to leading words. Require independent
    // free-prefix support before interpreting later clear words as a skipped start.
    final comparison = evidence.startComparison;
    final independentLater =
        comparison != null &&
        comparison.phonemes >= 20 &&
        comparison.expectedDistance >= 0.45 &&
        comparison.laterDistance <= 0.2 &&
        comparison.expectedDistance - comparison.laterDistance >= 0.2;
    final first = clear
        .where(
          (word) =>
              !independentLater || word.position.ayah == comparison.laterAyah,
        )
        .firstOrNull;
    if (!independentLater ||
        first == null ||
        first.position.ayah.surah != passage.start.surah ||
        first.position.ayah.ayah <= passage.start.ayah ||
        first.position.indexInAyah != 0) {
      _candidateIndex = null;
      return _assessment = const TilawaPassageStartAssessment(
        TilawaPassageStartStatus.awaitingEvidence,
      );
    }
    var consecutive = 1;
    while (clear.any(
      (word) => word.corpusWordIndex == first.corpusWordIndex + consecutive,
    )) {
      consecutive++;
    }
    final supported =
        _candidateIndex == first.corpusWordIndex &&
        _candidateWords >= 2 &&
        consecutive > _candidateWords &&
        evidence.phonemeCount > _candidatePhonemes;
    final alreadySupported =
        _assessment.status == TilawaPassageStartStatus.possibleSkippedStart &&
        _assessment.detected == first.position &&
        consecutive >= 2;
    _candidateIndex = first.corpusWordIndex;
    _candidateWords = consecutive;
    _candidatePhonemes = evidence.phonemeCount;
    return _assessment = TilawaPassageStartAssessment(
      supported || alreadySupported
          ? TilawaPassageStartStatus.possibleSkippedStart
          : TilawaPassageStartStatus.awaitingEvidence,
      detected: first.position,
    );
  }
}
