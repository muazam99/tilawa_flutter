import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/microphone.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

import 'metadata/demo_metadata_resolver.dart';

/// Consumer-owned state. No reading credit, persistence or page completion.
final class DemoController extends ChangeNotifier {
  final manifest = TilawaAssetManifest.zipformerV1();
  TilawaAssetStore? _store;
  TilawaPreparedAssets? _assets;
  TilawaAssetInstall? _installation;
  TilawaSession? _session;
  TilawaMicrophone? _microphone;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _captureSubscriptions = <StreamSubscription<dynamic>>[];
  Future<void>? _operation;
  bool _closed = false;
  bool _cleanupFailed = false;
  int _metadataGeneration = 0;
  int _lastSequence = 0;
  String? _runId;

  DemoMetadataResolver? fixture;
  bool busy = false;
  bool downloading = false;
  bool cancelling = false;
  bool metadataLoading = false;
  String status = 'Check local assets to begin.';
  String? error;
  String? metadataError;
  TilawaCaptureState captureState = TilawaCaptureState.idle;
  TilawaAssetProgress? downloadProgress;
  final Map<String, TilawaAssetProgress> fileProgress = {};
  TilawaAyahRef? ayah;
  TilawaWordProgress? progress;
  TilawaAyahMetadata? metadata;
  List<TilawaCandidate> candidates = const [];
  String transcript = '';
  TilawaTranscriptRepresentation representation =
      TilawaTranscriptRepresentation.unknown;
  TilawaSessionResult? result;
  TilawaTrackingState tracking = TilawaTrackingState.unknown;
  int verseObservations = 0;
  int progressObservations = 0;
  final List<String> notices = [];

  TilawaLifecycle? get lifecycle => _session?.snapshot.state;
  bool get hasSession => _session != null;
  bool get assetsAvailable => _assets != null;
  bool get canSetup => !busy && !hasSession && !_cleanupFailed;
  bool get capturing => captureState == TilawaCaptureState.capturing;
  bool get canStart =>
      !busy &&
      !_cleanupFailed &&
      (lifecycle == TilawaLifecycle.ready ||
          lifecycle == TilawaLifecycle.accepting) &&
      (captureState == TilawaCaptureState.idle ||
          captureState == TilawaCaptureState.failed);
  bool get canReset =>
      !busy &&
      !_cleanupFailed &&
      hasSession &&
      {
        TilawaLifecycle.ready,
        TilawaLifecycle.accepting,
        TilawaLifecycle.stopped,
        TilawaLifecycle.interrupted,
      }.contains(lifecycle);
  bool get canStop => !busy && capturing;
  bool get canRelease => !busy && hasSession && !_cleanupFailed;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _notice(String message) {
    notices.insert(0, message);
    if (notices.length > 8) notices.removeLast();
  }

  String _describe(Object failure) => failure is TilawaException
      ? '${failure.code}: ${failure.message}\nRecovery: ${failure.retryGuidance}'
      : '$failure';

  Future<void> _action(Future<void> Function() work) {
    if (busy || _closed) return Future.value();
    busy = true;
    error = null;
    _notify();
    final operation = (() async {
      try {
        await work();
      } catch (failure) {
        if (!_closed) {
          if (failure is TilawaException && failure.code == 'assetCancelled') {
            status = 'Download cancelled. Retry starts a fresh download.';
          } else {
            error = _describe(failure);
            status = 'Action failed. Correct the cause, then retry explicitly.';
          }
        }
      } finally {
        busy = false;
        _notify();
      }
    })();
    _operation = operation;
    return operation;
  }

  Future<void> _prepareStore() async {
    fixture ??= await DemoMetadataResolver.load();
    if (_store != null) return;
    final support = await getApplicationSupportDirectory();
    _store = TilawaAssetStore(Directory('${support.path}/tilawa-assets'));
    await _store!.cleanupInterruptedInstallations();
  }

  /// Checks integrity and opens installed assets without a network fallback.
  Future<void> checkLocal() => _action(() async {
    if (hasSession || _cleanupFailed) return;
    status = 'Verifying local installation...';
    _notify();
    await _prepareStore();
    if (_closed) return;
    _assets = await _store!.available(manifest);
    if (_closed) return;
    if (_assets == null) {
      status = 'Assets missing. Download once (74.7 MB), then reuse offline.';
      return;
    }
    await _open();
  });

  Future<void> download() => _action(() async {
    if (hasSession || _cleanupFailed) return;
    await _prepareStore();
    if (_closed) return;
    // A valid installation always wins over another network transfer.
    _assets = await _store!.available(manifest);
    if (_closed) return;
    if (_assets != null) {
      await _open();
      return;
    }
    downloading = true;
    cancelling = false;
    downloadProgress = null;
    fileProgress.clear();
    status = 'Downloading pinned assets...';
    _notify();
    final installation = _installation = _store!.download(manifest, retries: 2);
    final subscription = installation.progress.listen((value) {
      if (_closed) return;
      downloadProgress = value;
      fileProgress[value.file] = value;
      _notify();
    });
    try {
      _assets = await installation.completed;
    } finally {
      await subscription.cancel();
      _installation = null;
      downloading = cancelling = false;
      _notify();
    }
    if (!_closed) await _open();
  });

  void cancelDownload() {
    if (!downloading || cancelling) return;
    cancelling = true;
    status = 'Cancelling download and removing incomplete staging...';
    _installation?.cancel();
    _notify();
  }

  Future<void> _open() async {
    status = 'Opening local runtime. No microphone is started.';
    _notify();
    final session = await TilawaSession.open(
      assets: _assets!,
      metadataResolver: fixture,
    );
    if (_closed) {
      await session.dispose();
      return;
    }
    _session = session;
    captureState = TilawaCaptureState.idle;
    _clearRun(session.snapshot);
    _subscriptions.add(
      session.events.listen(
        (event) => _observe(session, event),
        onError: (Object failure) {
          if (!_closed && identical(session, _session)) {
            error = _describe(failure);
            _notify();
          }
        },
      ),
    );
    status = 'Ready. Tap Start microphone and recite. Audio stays on device.';
  }

  void _clearRun(TilawaSessionSnapshot snapshot) {
    _runId = snapshot.runId;
    _lastSequence = snapshot.lastSequence;
    _metadataGeneration++;
    ayah = null;
    progress = null;
    metadata = null;
    metadataError = null;
    metadataLoading = false;
    candidates = const [];
    transcript = '';
    representation = TilawaTranscriptRepresentation.unknown;
    tracking = snapshot.trackingState;
    result = null;
    verseObservations = progressObservations = 0;
    notices.clear();
  }

  void _observe(TilawaSession session, TilawaEvent event) {
    if (_closed ||
        !identical(session, _session) ||
        event.context.runId != session.snapshot.runId ||
        event.context.sequence <= _lastSequence) {
      return;
    }
    if (_runId != event.context.runId) {
      _clearRun(
        TilawaSessionSnapshot(
          sessionId: event.context.sessionId,
          runId: event.context.runId,
          state: session.snapshot.state,
          trackingState: session.snapshot.trackingState,
          submittedSamples: 0,
          processedSamples: 0,
          lastSequence: event.context.sequence - 1,
        ),
      );
    }
    _lastSequence = event.context.sequence;
    switch (event) {
      case TilawaVerseCandidates():
        candidates = event.candidates;
      case TilawaVerseMatched():
        verseObservations++;
        _select(session, event.ayah);
      case TilawaWordProgress():
        progressObservations++;
        _select(session, event.ayah);
        // Replace revisions, including shrinking or repeated snapshots.
        progress = event;
      case TilawaTranscriptUpdated():
        transcript = event.text;
        representation = event.representation;
      case TilawaTrackingStateObserved():
        tracking = event.state;
      case TilawaSessionEnded():
        // One result path. stop()/interrupt() return values are not aggregated.
        result = event.result;
        status = event.result.endReason == TilawaEndReason.interruption
            ? 'Interrupted (${event.result.interruption?.code}). Reset explicitly before restarting.'
            : 'Stopped. Reset for another run, or dispose the session.';
      case TilawaWarning():
        _notice(_describe(event.error));
      case TilawaFailure():
        error = _describe(event.error);
        status = 'Runtime failed. Dispose, then reopen local assets.';
      default:
        break;
    }
    _notify();
  }

  void _select(TilawaSession session, TilawaAyahRef selected) {
    if (selected == ayah) return;
    ayah = selected;
    progress = null;
    metadata = null;
    metadataError = null;
    metadataLoading = true;
    final generation = ++_metadataGeneration;
    final run = _runId;
    bool current() =>
        !_closed &&
        identical(_session, session) &&
        session.snapshot.runId == run &&
        _runId == run &&
        generation == _metadataGeneration &&
        ayah == selected;
    unawaited(() async {
      try {
        final value = await session.resolveMetadata(selected);
        if (current()) metadata = value;
      } catch (failure) {
        if (current()) metadataError = _describe(failure);
      } finally {
        if (current()) {
          metadataLoading = false;
          _notify();
        }
      }
    }());
  }

  Future<void> startMicrophone() => _action(() async {
    final session = _session!;
    if (_microphone == null) {
      final microphone = _microphone = await TilawaMicrophone.open(
        session: session,
      );
      _captureSubscriptions.add(
        microphone.states.listen((state) {
          if (_closed || !identical(microphone, _microphone)) return;
          captureState = state;
          _notify();
        }),
      );
      _captureSubscriptions.add(
        microphone.errors.listen((failure) {
          if (_closed || !identical(microphone, _microphone)) return;
          error = _describe(failure);
          _notice(
            'Input continuity affected. Wait for interruption, then Reset.',
          );
          _notify();
        }),
      );
    }
    if (_closed) return;
    await _microphone!.start();
    captureState = _microphone!.state;
    status = 'Listening locally. Tap Stop to finalize this run.';
  });

  Future<void> stopMicrophone() => _action(() async {
    await _microphone!.stopCapture();
    await _session!.stop();
    captureState = _microphone!.state;
  });

  Future<void> reset() => _action(() async {
    // Replace the helper to make capture recovery explicit after interruptions.
    await _microphone?.stopCapture();
    await _microphone?.dispose();
    for (final subscription in _captureSubscriptions) {
      await subscription.cancel();
    }
    _captureSubscriptions.clear();
    _microphone = null;
    captureState = TilawaCaptureState.idle;
    _metadataGeneration++;
    await _session!.reset();
    _clearRun(_session!.snapshot);
    status = 'Run reset. Microphone remains off until Start.';
  });

  Future<void> releaseSession() => _action(() async {
    await _release();
    status =
        'Session disposed. Verified files retained. Reopen local, including offline.';
  });

  Future<void> _release() async {
    _metadataGeneration++;
    final session = _session;
    try {
      // Session owns the attached microphone; no implicit finalization.
      await session?.dispose();
    } catch (_) {
      _cleanupFailed = true;
      _notice(
        'Cleanup could not be confirmed. Restart the app; do not delete leased files.',
      );
      rethrow;
    } finally {
      for (final subscription in [
        ..._subscriptions,
        ..._captureSubscriptions,
      ]) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      _captureSubscriptions.clear();
    }
    _session = null;
    _microphone = null;
    captureState = TilawaCaptureState.disposed;
    metadataLoading = false;
  }

  /// Widget teardown cancels setup and waits for acquired resources to close.
  @override
  void dispose() {
    _closed = true;
    _metadataGeneration++;
    _installation?.cancel();
    final pending = _operation;
    unawaited(() async {
      try {
        await pending;
        await _release();
      } catch (failure) {
        // No recitation text or references are written to device logs.
        debugPrint(
          'Tilawa example teardown: ${failure is TilawaException ? failure.code : failure.runtimeType}',
        );
      }
    }());
    super.dispose();
  }
}
