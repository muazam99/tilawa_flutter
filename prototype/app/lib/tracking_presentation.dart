// Consumer-owned presentation only. No repeat credit, coverage or pagesRead.
import 'package:tilawa_flutter/tilawa_flutter.dart';

final class TrackingPresentation {
  String? sessionId, runId;
  int lastSequence = 0, metadataGeneration = 0;
  TilawaLifecycle lifecycle = TilawaLifecycle.ready;
  TilawaTrackingState tracking = TilawaTrackingState.unknown;
  TilawaAyahRef? ayah;
  List<TilawaCandidate> candidates = const [];
  TilawaWordProgress? progress;
  TilawaAyahMetadata? metadata;
  String transcript = '';
  bool lostDiagnostic = false;
  TilawaSessionResult? result;

  void accept(TilawaEvent event) {
    final context = event.context;
    if (sessionId != null && context.sessionId != sessionId) {
      throw StateError('Presentation belongs to a different session');
    }
    if (context.sequence <= lastSequence) {
      throw StateError('Out-of-order event');
    }
    sessionId = context.sessionId;
    lastSequence = context.sequence;
    if (runId != context.runId) {
      runId = context.runId;
      ayah = null;
      progress = null;
      metadata = null;
      candidates = const [];
      transcript = '';
      result = null;
      lostDiagnostic = false;
      tracking = TilawaTrackingState.unknown;
      metadataGeneration++;
    }
    switch (event) {
      case TilawaStateChanged():
        lifecycle = event.current;
      case TilawaTrackingStateObserved():
        tracking = event.state;
      case TilawaVerseCandidates():
        candidates = event.candidates;
      case TilawaVerseMatched():
        _select(event.ayah);
      case TilawaWordProgress():
        _select(event.ayah);
        // Replace even if repeated, shrinking, revised or jumping backwards.
        // Neither cursor position nor matchedIndices is certified correctness.
        progress = event;
        lostDiagnostic = false;
      case TilawaTranscriptUpdated():
        transcript = event.text;
      case TilawaDiagnostic():
        if (event.name == 'lost') lostDiagnostic = true;
      case TilawaSessionEnded():
        result = event.result;
      default:
        break;
    }
  }

  void _select(TilawaAyahRef selected) {
    if (selected == ayah) return;
    ayah = selected;
    progress = null;
    metadata = null;
    metadataGeneration++;
  }

  bool applyMetadata(
    TilawaAyahMetadata? value, {
    required String requestedRun,
    required int generation,
    required TilawaAyahRef requestedAyah,
  }) {
    if (runId != requestedRun ||
        metadataGeneration != generation ||
        ayah != requestedAyah ||
        (value != null && value.ayah != requestedAyah)) {
      return false;
    }
    metadata = value;
    return true;
  }
}
