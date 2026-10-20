import '../models.dart';

// Shared by native and WebView transports. Corpus bounds are checked by session.
Never _invalid() => throw const TilawaException(
  'invalidEngineOutput',
  'Malformed correction observation.',
);

int _integer(Object? value) => value is int && value >= 0 ? value : _invalid();

TilawaWordRef _position(Object? value) {
  if (value is! Map) _invalid();
  final surah = _integer(value['surah']);
  final ayah = _integer(value['ayah']);
  if (surah < 1 || surah > 114 || ayah < 1) _invalid();
  return TilawaWordRef(TilawaAyahRef(surah, ayah), _integer(value['word']));
}

TilawaCorrectionIssue parseCorrectionIssue(Object? value) {
  if (value is! Map) _invalid();
  final kind = switch (value['kind']) {
    'possible_omission' => TilawaCorrectionKind.possibleOmission,
    'possible_substitution' => TilawaCorrectionKind.possibleSubstitution,
    'possible_vowel' => TilawaCorrectionKind.possibleVowel,
    'possible_repetition' => TilawaCorrectionKind.possibleRepetition,
    'possible_skipped_ayah' => TilawaCorrectionKind.possibleSkippedAyah,
    'unclear_ayah' => TilawaCorrectionKind.unclearAyah,
    _ => _invalid(),
  };
  final words = value['words'] == null ? 1 : _integer(value['words']);
  final source = value['source'];
  if (words < 1 ||
      (source != null && source != 'ayah_order' && source != 'similar_verse')) {
    _invalid();
  }
  return TilawaCorrectionIssue(
    position: _position(value),
    corpusWordIndex: _integer(value['wordIndex']),
    kind: kind,
    words: words,
    source: source as String?,
  );
}

TilawaCorrectionState parseCorrectionState(Object? value) {
  if (value is! Map) _invalid();
  final phase = switch (value['phase']) {
    'idle' => TilawaCorrectionPhase.idle,
    'error' => TilawaCorrectionPhase.error,
    'retrying' => TilawaCorrectionPhase.retrying,
    'corrected' => TilawaCorrectionPhase.corrected,
    _ => _invalid(),
  };
  final outcome = switch (value['outcome']) {
    null => null,
    'dismissed' => TilawaCorrectionOutcome.dismissed,
    'deferred' => TilawaCorrectionOutcome.deferred,
    'corrected' => TilawaCorrectionOutcome.corrected,
    _ => _invalid(),
  };
  final issue = value['issue'] == null
      ? null
      : parseCorrectionIssue(value['issue']);
  final resume = value['resume'] == null ? null : _position(value['resume']);
  if ((phase != TilawaCorrectionPhase.idle &&
          (issue == null || resume == null)) ||
      (phase == TilawaCorrectionPhase.corrected &&
          outcome != TilawaCorrectionOutcome.corrected)) {
    _invalid();
  }
  return TilawaCorrectionState(
    phase: phase,
    issue: issue,
    resume: resume,
    attempt: _integer(value['attempt']),
    outcome: outcome,
  );
}

String correctionActionName(TilawaCorrectionAction action) => switch (action) {
  TilawaCorrectionAction.retry => 'retry',
  TilawaCorrectionAction.stopRetry => 'stop_retry',
  TilawaCorrectionAction.dismiss => 'dismiss',
  TilawaCorrectionAction.reviewLater => 'review_later',
  TilawaCorrectionAction.continueReading => 'continue',
  TilawaCorrectionAction.close => 'close',
};

Map<String, Object?>? expectedPassageData(TilawaExpectedPassage? passage) =>
    passage == null
    ? null
    : {
        'surah': passage.start.surah,
        'ayah': passage.start.ayah,
        'ayahEnd': passage.lastAyah,
      };
