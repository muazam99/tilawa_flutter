import 'dart:collection';

enum TilawaLifecycle {
  ready,
  accepting,
  stopping,
  stopped,
  interrupting,
  interrupted,
  resetting,
  disposing,
  disposed,
  failed,
}

enum TilawaTrackingState { searching, tracking, unknown }

enum TilawaEndReason { stop, interruption }

enum TilawaFinalization { complete, incomplete }

enum TilawaTranscriptRepresentation { phonemes, arabicText, unknown }

enum TilawaRecitationMode { tracking, correction }

enum TilawaStructuralCorrection { off, onStop, onPause }

/// Aligner classifications, not certified recitation/pronunciation grades.
enum TilawaWordVerdictState { correct, uncertain, wrong, skipped, pending }

enum TilawaCorrectionPhase { idle, error, retrying, corrected }

enum TilawaCorrectionAction {
  retry,
  stopRetry,
  dismiss,
  reviewLater,
  continueReading,
  close,
}

enum TilawaCorrectionOutcome { dismissed, deferred, corrected }

enum TilawaCorrectionKind {
  possibleOmission,
  possibleSubstitution,
  possibleVowel,
  possibleRepetition,
  possibleSkippedAyah,
  unclearAyah,
}

/// Inclusive ayah range in one surah. Only effective in correction mode.
final class TilawaExpectedPassage {
  const TilawaExpectedPassage(this.start, {this.ayahEnd});
  final TilawaAyahRef start;
  final int? ayahEnd;
  int get lastAyah => ayahEnd ?? start.ayah;

  void validate() {
    if (start.surah < 1 ||
        start.surah > 114 ||
        start.ayah < 1 ||
        lastAyah < start.ayah) {
      throw const TilawaException('invalidInput', 'Invalid expected passage.');
    }
  }
}

/// A possible upstream issue, not a certified pronunciation/tajweed grade.
final class TilawaCorrectionIssue {
  const TilawaCorrectionIssue({
    required this.position,
    required this.corpusWordIndex,
    required this.kind,
    this.words = 1,
    this.source,
  });
  final TilawaWordRef position;
  final int corpusWordIndex;
  final TilawaCorrectionKind kind;
  final int words;
  final String? source;
  @override
  bool operator ==(Object other) =>
      other is TilawaCorrectionIssue &&
      position == other.position &&
      corpusWordIndex == other.corpusWordIndex &&
      kind == other.kind &&
      words == other.words &&
      source == other.source;
  @override
  int get hashCode =>
      Object.hash(position, corpusWordIndex, kind, words, source);
}

/// Correction state is separate from session lifecycle. Error/corrected pause
/// recognition until an explicit action. Retry starts at the issue's ayah start.
final class TilawaCorrectionState {
  const TilawaCorrectionState({
    this.phase = TilawaCorrectionPhase.idle,
    this.issue,
    this.resume,
    this.attempt = 0,
    this.outcome,
  });
  final TilawaCorrectionPhase phase;
  final TilawaCorrectionIssue? issue;
  final TilawaWordRef? resume;
  final int attempt;
  final TilawaCorrectionOutcome? outcome;
  bool get awaitsAction =>
      phase == TilawaCorrectionPhase.error ||
      phase == TilawaCorrectionPhase.corrected;
  @override
  bool operator ==(Object other) =>
      other is TilawaCorrectionState &&
      phase == other.phase &&
      issue == other.issue &&
      resume == other.resume &&
      attempt == other.attempt &&
      outcome == other.outcome;
  @override
  int get hashCode => Object.hash(phase, issue, resume, attempt, outcome);
}

/// SDK failure with a stable code and suggested recovery category.
/// Runtime or disposal failures require a fresh session, not an input retry.
final class TilawaException implements Exception {
  const TilawaException(this.code, this.message, {this.operationId});
  final String code;
  final String message;
  final int? operationId;
  String get category {
    if (code.startsWith('asset') || code == 'assetsInUse') return 'assets';
    if (code.startsWith('metadata')) return 'metadata';
    if (code.startsWith('unsupported')) return 'unsupported';
    if (code == 'incompatibleAssets') return 'compatibility';
    if (code == 'disposed' || code == 'invalidState') return 'invalidState';
    if (code == 'invalidAudio' ||
        code == 'audioOverrun' ||
        code.startsWith('capture') ||
        code.startsWith('microphone')) {
      return 'audio';
    }
    if (code == 'invalidInput') return 'invalidInput';
    if (code == 'disposalFailed') return 'disposal';
    return 'runtime';
  }

  String get retryGuidance => category == 'runtime' || category == 'disposal'
      ? 'createNewSession'
      : code == 'audioOverrun'
      ? 'restoreInputContinuityBeforeRetry'
      : 'correctCauseBeforeRetry';
  @override
  String toString() => 'TilawaException($code): $message';
}

/// Quran reference with 1-based surah and ayah numbers.
final class TilawaAyahRef {
  const TilawaAyahRef(this.surah, this.ayah);
  final int surah;
  final int ayah;
  @override
  bool operator ==(Object other) =>
      other is TilawaAyahRef && surah == other.surah && ayah == other.ayah;
  @override
  int get hashCode => Object.hash(surah, ayah);
  @override
  String toString() => '$surah:$ayah';
}

/// Corpus word reference. [indexInAyah] is 0-based, independent of display text.
final class TilawaWordRef {
  const TilawaWordRef(this.ayah, this.indexInAyah);
  final TilawaAyahRef ayah;
  final int indexInAyah;
  @override
  bool operator ==(Object other) =>
      other is TilawaWordRef &&
      ayah == other.ayah &&
      indexInAyah == other.indexInAyah;
  @override
  int get hashCode => Object.hash(ayah, indexInAyah);
}

/// Recognition policy and bounded audio admission/cleanup budgets.
/// Scores and matching thresholds are engine values, not calibrated accuracy.
/// Deadlines bound SDK waiting; they cannot preempt native OS calls.
final class TilawaRecognitionConfig {
  const TilawaRecognitionConfig({
    this.mode = TilawaRecitationMode.tracking,
    this.expectedPassage,
    this.structuralCorrection = TilawaStructuralCorrection.off,
    this.wordEvidence = false,
    this.minWordFraction = 0.5,
    this.enableFallback = true,
    this.fallbackMaxDistance = 0.5,
    this.stayOnSurah = false,
    this.tailDuration = const Duration(seconds: 2),
    this.diagnostics = false,
    this.maxChunkDuration = const Duration(seconds: 1),
    this.maxOutstandingAudioDuration = const Duration(seconds: 2),
    this.interruptionDeadline = const Duration(seconds: 10),
    this.disposalDeadline = const Duration(seconds: 10),
  });
  final TilawaRecitationMode mode;
  final TilawaExpectedPassage? expectedPassage;
  final TilawaStructuralCorrection structuralCorrection;
  final bool wordEvidence;
  final double minWordFraction;

  /// Whole-ayah fallback is tracking-only. It fabricates all-ok tallies and
  /// therefore cannot be used as correction evidence or escape a passage bound.
  final bool enableFallback;
  bool get effectiveFallback =>
      mode == TilawaRecitationMode.tracking && enableFallback;
  final double fallbackMaxDistance;
  final bool stayOnSurah;
  final Duration tailDuration;
  final bool diagnostics;
  final Duration maxChunkDuration;
  final Duration maxOutstandingAudioDuration;
  final Duration interruptionDeadline;
  final Duration disposalDeadline;
  int get maxChunkSamples => maxChunkDuration.inMicroseconds * 16000 ~/ 1000000;
  int get maxOutstandingSamples =>
      maxOutstandingAudioDuration.inMicroseconds * 16000 ~/ 1000000;
  void validate() {
    expectedPassage?.validate();
    if (mode != TilawaRecitationMode.correction &&
        (structuralCorrection != TilawaStructuralCorrection.off ||
            wordEvidence)) {
      throw const TilawaException(
        'invalidInput',
        'Structural checks and word evidence require correction mode.',
      );
    }
    if (expectedPassage != null && mode != TilawaRecitationMode.correction) {
      throw const TilawaException(
        'invalidInput',
        'Expected passages require correction mode.',
      );
    }
    if (!minWordFraction.isFinite ||
        minWordFraction <= 0 ||
        minWordFraction > 1 ||
        !fallbackMaxDistance.isFinite ||
        fallbackMaxDistance < 0 ||
        fallbackMaxDistance > 1 ||
        tailDuration.isNegative ||
        tailDuration > const Duration(seconds: 5) ||
        maxChunkSamples <= 0 ||
        maxOutstandingSamples < maxChunkSamples ||
        interruptionDeadline <= Duration.zero ||
        disposalDeadline <= Duration.zero) {
      throw const TilawaException(
        'invalidInput',
        'Invalid recognition configuration.',
      );
    }
    for (final duration in [
      tailDuration,
      maxChunkDuration,
      maxOutstandingAudioDuration,
    ]) {
      if (duration.inMicroseconds * 16000 % 1000000 != 0) {
        throw const TilawaException(
          'invalidInput',
          'Audio durations must map to whole 16 kHz samples.',
        );
      }
    }
  }
}

/// Observations available from an adapter, rather than accuracy guarantees.
final class TilawaCapabilities {
  TilawaCapabilities({
    required Set<String> observations,
    this.transcriptRepresentation = TilawaTranscriptRepresentation.phonemes,
    this.finalSequence = true,
    this.sampledTrackingState = true,
    this.correction = false,
    this.wordEvidence = false,
    this.structuralCorrection = false,
  }) : observations = Set.unmodifiable(observations);
  final Set<String> observations;
  final TilawaTranscriptRepresentation transcriptRepresentation;
  final bool finalSequence;
  final bool sampledTrackingState;
  final bool correction;
  final bool wordEvidence, structuralCorrection;
  bool get exactWordTimestamps => false;
}

final class TilawaSessionInfo {
  const TilawaSessionInfo({
    required this.engineId,
    required this.engineVersion,
    required this.upstreamCommit,
    required this.manifestId,
    required this.corpusSha256,
    required this.segmentationId,
    required this.adapterId,
    required this.adapterVersion,
    required this.platform,
    required this.capabilities,
    required this.config,
  });
  final String engineId, engineVersion, upstreamCommit, manifestId;
  final String corpusSha256,
      segmentationId,
      adapterId,
      adapterVersion,
      platform;
  final TilawaCapabilities capabilities;
  final TilawaRecognitionConfig config;
}

/// Session/run identity and event ordering for rejecting stale UI updates.
final class TilawaEventContext {
  const TilawaEventContext({
    required this.sessionId,
    required this.runId,
    required this.sequence,
    required this.emittedAt,
    required this.elapsedSinceOpen,
    required this.inputPositionSamples,
  });
  final String sessionId, runId;
  final int sequence;
  final DateTime emittedAt;
  final Duration elapsedSinceOpen;
  final int? inputPositionSamples;
}

sealed class TilawaEvent {
  const TilawaEvent(this.context);
  final TilawaEventContext context;
}

final class TilawaStateChanged extends TilawaEvent {
  const TilawaStateChanged(super.context, this.previous, this.current);
  final TilawaLifecycle previous, current;
}

final class TilawaTrackingStateObserved extends TilawaEvent {
  const TilawaTrackingStateObserved(super.context, this.state);
  final TilawaTrackingState state;
}

final class TilawaCandidate {
  const TilawaCandidate({
    required this.ayah,
    required this.score,
    required this.rank,
    required this.source,
    this.ayahEnd,
  });
  final TilawaAyahRef ayah;
  final int? ayahEnd;
  final double score;
  final int rank;
  final String source;
}

final class TilawaVerseCandidates extends TilawaEvent {
  TilawaVerseCandidates(
    super.context,
    Iterable<TilawaCandidate> candidates, {
    required this.stable,
    required this.finalFlush,
  }) : candidates = List.unmodifiable(candidates);
  final List<TilawaCandidate> candidates;
  final bool stable, finalFlush;
}

final class TilawaSurroundingVerse {
  const TilawaSurroundingVerse(this.ayah, this.text, this.isCurrent);
  final TilawaAyahRef ayah;
  final String text;
  final bool isCurrent;
}

/// Engine verse match. A fallback match need not have word-progress evidence.
final class TilawaVerseMatched extends TilawaEvent {
  TilawaVerseMatched(
    super.context,
    this.ayah,
    this.score, {
    this.text,
    this.surahName,
    Iterable<TilawaSurroundingVerse> surrounding = const [],
  }) : surrounding = List.unmodifiable(surrounding);
  final TilawaAyahRef ayah;
  final double score;
  final String? text, surahName;
  final List<TilawaSurroundingVerse> surrounding;
  String get provenance => 'notProvided';
}

/// Current 0-based word snapshot; replace previous indices rather than unioning.
/// Includes uncertain matches and revisions, not certified words read.
final class TilawaWordProgress extends TilawaEvent {
  TilawaWordProgress(
    super.context,
    this.ayah,
    this.wordIndex,
    this.totalWords,
    Iterable<int> matchedIndices,
  ) : matchedIndices = List.unmodifiable(matchedIndices);
  final TilawaAyahRef ayah;
  final int wordIndex, totalWords;
  final List<int> matchedIndices;
}

final class TilawaCorrectionChanged extends TilawaEvent {
  const TilawaCorrectionChanged(super.context, this.state);
  final TilawaCorrectionState state;
}

/// Current replacement alignment snapshot. Non-pending words can still revise.
/// No acoustic timestamp or speech-presence probability is fabricated here.
final class TilawaWordVerdict {
  const TilawaWordVerdict({
    required this.position,
    required this.corpusWordIndex,
    required this.state,
    required this.distance,
    required this.margin,
    required this.heardRatio,
    required this.vowelErrors,
    required this.vowelMargin,
    this.gop,
    this.gopNone,
    this.repetitionGain,
  });
  final TilawaWordRef position;
  final int corpusWordIndex;
  final TilawaWordVerdictState state;
  final double distance, margin, heardRatio, vowelMargin;
  final int vowelErrors;
  final double? gop, gopNone, repetitionGain;
}

/// Replace, never union. [revision] increases within a run; [attempt] separates
/// correction/practice boundaries. [audioEnded] is not an immutable verdict seal.
final class TilawaWordEvidence extends TilawaEvent {
  TilawaWordEvidence(
    super.context, {
    required this.revision,
    required this.attempt,
    required this.phonemeCount,
    required this.audioEnded,
    required Iterable<TilawaWordVerdict> words,
    this.startComparison,
  }) : words = List.unmodifiable(words);
  final int revision, attempt, phonemeCount;
  final bool audioEnded;
  final List<TilawaWordVerdict> words;
  final TilawaStartComparison? startComparison;
}

/// Bounded free-decode prefix comparison, independent of forced tracker cursor.
/// Distances are phoneme edit costs, not probabilities. Experimental evidence.
final class TilawaStartComparison {
  const TilawaStartComparison({
    required this.laterAyah,
    required this.expectedDistance,
    required this.laterDistance,
    required this.phonemes,
  });
  final TilawaAyahRef laterAyah;
  final double expectedDistance, laterDistance;
  final int phonemes;
}

/// Nonblocking upstream note. Unlike an error, it does not pause recognition.
final class TilawaCorrectionNote extends TilawaEvent {
  const TilawaCorrectionNote(super.context, this.issue);
  final TilawaCorrectionIssue issue;
}

/// Input drained but not analyzed while upstream awaits a correction action.
/// Stop/dispose capture before taking an action. This audio cannot enter a retry.
final class TilawaAudioDiscarded extends TilawaEvent {
  const TilawaAudioDiscarded(super.context, this.samples);
  final int samples;
  String get reason => 'correctionAwaitingAction';
}

/// Replacement transcript snapshot in the adapter's declared representation.
/// The default engine produces phonemes, not ordinary Arabic text.
final class TilawaTranscriptUpdated extends TilawaEvent {
  const TilawaTranscriptUpdated(
    super.context,
    this.text,
    this.score,
    this.representation,
  );
  final String text;
  final double score;
  final TilawaTranscriptRepresentation representation;
}

final class TilawaSequenceVerse {
  const TilawaSequenceVerse(this.ayah, this.score);
  final TilawaAyahRef ayah;
  final double score;
}

final class TilawaFinalSequenceObserved extends TilawaEvent {
  TilawaFinalSequenceObserved(
    super.context,
    Iterable<TilawaSequenceVerse> verses,
    this.score,
  ) : verses = List.unmodifiable(verses);
  final List<TilawaSequenceVerse> verses;
  final double score;
}

final class TilawaDiagnostic extends TilawaEvent {
  TilawaDiagnostic(
    super.context,
    this.name,
    this.sourceTimestamp,
    Map<String, Object?> payload,
  ) : payload = freezeMap(payload);
  final String name;
  final DateTime? sourceTimestamp;
  final Map<String, Object?> payload;
}

final class TilawaUnknownObservation extends TilawaEvent {
  TilawaUnknownObservation(
    super.context,
    this.kind,
    Map<String, Object?> payload,
  ) : payload = freezeMap(payload);
  final String kind;
  final Map<String, Object?> payload;
}

final class TilawaWarning extends TilawaEvent {
  const TilawaWarning(super.context, this.error);
  final TilawaException error;
}

final class TilawaFailure extends TilawaEvent {
  const TilawaFailure(super.context, this.error);
  final TilawaException error;
}

final class TilawaSessionEnded extends TilawaEvent {
  const TilawaSessionEnded(super.context, this.result);
  final TilawaSessionResult result;
}

final class TilawaInterruption {
  const TilawaInterruption(this.code);
  final String code;
}

final class TilawaFeedReceipt {
  const TilawaFeedReceipt(
    this.startSample,
    this.endSample,
    this.processedThrough,
  );
  final int startSample, endSample, processedThrough;
}

/// Finalized operation evidence and the engine's non-exhaustive verse sequence.
/// Complete finalization means draining succeeded, not every verse was found.
/// Consume either the returned result or SessionEnded for aggregation, not both.
final class TilawaSessionResult {
  TilawaSessionResult({
    required this.sessionId,
    required this.runId,
    required this.endReason,
    required this.finalization,
    required Iterable<TilawaSequenceVerse>? engineSequence,
    this.sequenceScore,
    required this.transcript,
    required this.representation,
    required this.submittedSamples,
    required this.processedSamples,
    this.interruption,
    Iterable<TilawaException> warnings = const [],
  }) : engineSequence = engineSequence == null
           ? null
           : List.unmodifiable(engineSequence),
       warnings = List.unmodifiable(warnings);
  final String sessionId, runId;
  final TilawaEndReason endReason;
  final TilawaFinalization finalization;
  final List<TilawaSequenceVerse>? engineSequence;
  final double? sequenceScore;
  final String transcript;
  final TilawaTranscriptRepresentation representation;
  final int submittedSamples, processedSamples;
  final TilawaInterruption? interruption;
  final List<TilawaException> warnings;
}

final class TilawaSessionSnapshot {
  const TilawaSessionSnapshot({
    required this.sessionId,
    required this.runId,
    required this.state,
    required this.trackingState,
    required this.submittedSamples,
    required this.processedSamples,
    required this.lastSequence,
    this.lastResult,
    this.correction = const TilawaCorrectionState(),
    this.expectedPassage,
    this.controlPending = false,
  });
  final String sessionId, runId;
  final TilawaLifecycle state;
  final TilawaTrackingState trackingState;
  final int submittedSamples, processedSamples, lastSequence;
  final TilawaSessionResult? lastResult;
  final TilawaCorrectionState correction;
  final TilawaExpectedPassage? expectedPassage;
  final bool controlPending;
}

final class TilawaMetadataDescriptor {
  const TilawaMetadataDescriptor({
    required this.version,
    required this.edition,
    required this.corpusSha256,
    required this.segmentationId,
  });
  final String version, edition, corpusSha256, segmentationId;
}

final class TilawaWordMetadata {
  TilawaWordMetadata(
    this.indexInAyah, {
    Iterable<String> displayWordIds = const [],
    Iterable<int> pages = const [],
    Iterable<int> juz = const [],
  }) : displayWordIds = List.unmodifiable(displayWordIds),
       pages = List.unmodifiable(pages),
       juz = List.unmodifiable(juz);
  final int indexInAyah;
  final List<String> displayWordIds;
  final List<int> pages, juz;
}

final class TilawaAyahMetadata {
  TilawaAyahMetadata({
    required this.ayah,
    required this.descriptor,
    required this.recognitionWordCount,
    this.text,
    this.ayahOnly = false,
    Iterable<TilawaWordMetadata> words = const [],
    Iterable<int> pages = const [],
    Iterable<int> juz = const [],
  }) : words = List.unmodifiable(words),
       pages = List.unmodifiable(pages),
       juz = List.unmodifiable(juz);
  final TilawaAyahRef ayah;
  final TilawaMetadataDescriptor descriptor;
  final int recognitionWordCount;
  final bool ayahOnly;
  final String? text;
  final List<TilawaWordMetadata> words;
  final List<int> pages, juz;
}

/// Optional caller-owned display metadata compatible with the pinned corpus.
/// Identity and mappings are validated; actual label/layout accuracy is yours.
/// Awaited lookups must still be guarded against run/ayah changes by consumers.
abstract interface class TilawaMetadataResolver {
  TilawaMetadataDescriptor get descriptor;
  Future<TilawaAyahMetadata?> resolveAyah(TilawaAyahRef ayah);
}

Map<String, Object?> freezeMap(Map<String, Object?> value) =>
    UnmodifiableMapView(value.map((key, item) => MapEntry(key, _freeze(item))));
Object? _freeze(Object? value) {
  if (value is Map) {
    return freezeMap(value.map((key, item) => MapEntry(key as String, item)));
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw const TilawaException(
    'invalidEngineOutput',
    'Payload must contain JSON-compatible values.',
  );
}
