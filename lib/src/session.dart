import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'adapter.dart';
import 'assets.dart';
import 'capture_binding.dart';
import 'models.dart';
import 'runtime/webview_adapter.dart';
import 'runtime/native_adapter.dart';

/// One owned runtime with serialized, reset-delimited recognition runs.
final class TilawaSession {
  TilawaSession._(this._assets, this._config, this._resolver);
  final TilawaPreparedAssets _assets;
  final TilawaRecognitionConfig _config;
  final TilawaMetadataResolver? _resolver;
  TilawaMetadataDescriptor? _metadataDescriptor;
  TilawaException? _metadataBindingError;
  late final TilawaEngineAdapter _adapter;
  late final TilawaSessionInfo info;
  final _events = StreamController<TilawaEvent>.broadcast();
  final _clock = Stopwatch();
  final _sessionId = newTilawaId();
  String _runId = newTilawaId();
  TilawaLifecycle _state = TilawaLifecycle.ready;
  TilawaTrackingState _tracking = TilawaTrackingState.unknown;
  Future<void> _queue = Future.value();
  Future<void>? _resetting, _disposing;
  Future<TilawaSessionResult>? _ending;
  List<Map<String, Object?>>? _batch;
  int _submitted = 0,
      _processed = 0,
      _reserved = 0,
      _sequence = 0,
      _operation = 0;
  String _transcript = '';
  TilawaException? _fatal;
  TilawaSessionResult? _lastResult;
  bool _quarantined = false;
  final _wordCounts = <TilawaAyahRef, int>{};

  /// Verifies and leases [assets], then opens an independently owned adapter.
  /// Android uses native ONNX in a worker. iOS uses provisional WebView WASM.
  static Future<TilawaSession> open({
    required TilawaPreparedAssets assets,
    TilawaRecognitionConfig config = const TilawaRecognitionConfig(),
    TilawaMetadataResolver? metadataResolver,
    TilawaEngineAdapterFactory? adapterFactory,
  }) async {
    config.validate();
    assets.retain();
    final session = TilawaSession._(assets, config, metadataResolver);
    TilawaEngineAdapter? acquired;
    try {
      // Bind identity once. A mutable caller-owned resolver must not silently
      // switch editions/versions while an existing session is using it.
      if (metadataResolver != null) {
        try {
          session._metadataDescriptor = metadataResolver.descriptor;
        } catch (error) {
          session._metadataBindingError = TilawaException(
            'metadataResolutionFailed',
            'Metadata descriptor: $error',
          );
        }
      }
      await assets.verify();
      session._adapter = acquired =
          await (adapterFactory ??
                  (Platform.isAndroid
                      ? const TilawaNativeAdapterFactory()
                      : const TilawaWebViewAdapterFactory()))
              .create(assets, config, session._observe);
      final manifest = assets.manifest;
      session.info = TilawaSessionInfo(
        engineId: manifest.engineId,
        engineVersion: manifest.engineVersion,
        upstreamCommit: manifest.upstreamCommit,
        manifestId: manifest.id,
        corpusSha256: manifest.corpusSha256,
        segmentationId: manifest.segmentationId,
        adapterId: session._adapter.id,
        adapterVersion: session._adapter.version,
        platform: Platform.operatingSystem,
        capabilities: session._adapter.capabilities,
        config: config,
      );
      session._clock.start();
      return session;
    } catch (error) {
      if (acquired != null) {
        try {
          await acquired.dispose().timeout(config.disposalDeadline);
        } catch (cleanup) {
          unawaited(session._events.close());
          throw TilawaException(
            'runtimeInitializationFailed',
            '$error; cleanup failed: $cleanup',
          );
        }
      }
      assets.release();
      await session._events.close();
      throw error is TilawaException
          ? error
          : TilawaException('runtimeInitializationFailed', '$error');
    }
  }

  Stream<TilawaEvent> get events => _events.stream;
  TilawaSessionSnapshot get snapshot => TilawaSessionSnapshot(
    sessionId: _sessionId,
    runId: _runId,
    state: _state,
    trackingState: _tracking,
    submittedSamples: _submitted,
    processedSamples: _processed,
    lastSequence: _sequence,
    lastResult: _lastResult,
  );
  TilawaEventContext _context() => TilawaEventContext(
    sessionId: _sessionId,
    runId: _runId,
    sequence: ++_sequence,
    emittedAt: DateTime.now().toUtc(),
    elapsedSinceOpen: _clock.elapsed,
    inputPositionSamples: _processed,
  );
  void _stateTo(TilawaLifecycle state) {
    if (_state == state) return;
    final old = _state;
    _state = state;
    _events.add(TilawaStateChanged(_context(), old, state));
  }

  void _observe(Map<String, Object?> observation) {
    if (_quarantined || _state == TilawaLifecycle.disposed) return;
    if (observation['type'] == '_runtime_failure') {
      if (_clock.isRunning) {
        _quarantined = true;
        _fail(
          TilawaException('bridgeDisconnected', '${observation['message']}'),
        );
      }
      return;
    }
    final batch = _batch;
    if (batch == null) {
      // Initialization/reset may emit nothing. Unscoped output is not allowed
      // to leak into another run; it is rejected as an adapter violation.
      if (_clock.isRunning) {
        _fail(
          const TilawaException(
            'invalidEngineOutput',
            'Unscoped adapter observation.',
          ),
        );
      }
      return;
    }
    batch.add(freezeMap(observation));
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final future = _queue.then((_) => operation());
    _queue = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future;
  }

  void _usable() {
    if (_state == TilawaLifecycle.disposed || _quarantined) {
      throw _fatal ??
          const TilawaException(
            'disposed',
            'Session cannot accept operations.',
          );
    }
    if (_fatal != null) throw _fatal!;
  }

  void _fail(TilawaException error) {
    if (_fatal != null || _state == TilawaLifecycle.disposed) return;
    _fatal = error;
    if (_state != TilawaLifecycle.disposing) {
      _stateTo(TilawaLifecycle.failed);
      _events.add(TilawaFailure(_context(), error));
    }
  }

  Future<TilawaEngineSnapshot> _engine(
    Future<TilawaEngineSnapshot> Function() operation, {
    Duration? timeout,
    int? expectedSamples,
    bool finalizing = false,
    bool incompleteOnFailure = false,
  }) async {
    _usable();
    final id = ++_operation;
    _batch = [];
    try {
      final pending = operation();
      final result = await (timeout == null
          ? pending
          : pending.timeout(timeout));
      _usable();
      if (result.consumedSamples < _processed ||
          result.consumedSamples > _submitted ||
          (expectedSamples != null &&
              result.consumedSamples != expectedSamples)) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Invalid processed audio position.',
        );
      }
      final batch = _batch!;
      await _validateReferences(batch);
      _usable();
      // Validate every observation before committing this operation's batch.
      final oldPosition = _processed;
      _processed = result.consumedSamples;
      final oldSequence = _sequence;
      final parsed = <TilawaEvent>[];
      try {
        for (final observation in batch) {
          final event = _parse(observation);
          if (event != null) parsed.add(event);
        }
        final finals = parsed.whereType<TilawaFinalSequenceObserved>().toList();
        if (finalizing) {
          final sequence = result.sequence;
          if (finals.length != 1 ||
              sequence == null ||
              result.score != finals.single.score ||
              sequence.length != finals.single.verses.length ||
              List.generate(sequence.length, (index) => index).any(
                (index) =>
                    sequence[index].ayah != finals.single.verses[index].ayah ||
                    sequence[index].score != finals.single.verses[index].score,
              )) {
            throw const TilawaException(
              'invalidEngineOutput',
              'Final snapshot and observation disagree.',
            );
          }
        } else if (finals.isNotEmpty || result.sequence != null) {
          throw const TilawaException(
            'invalidEngineOutput',
            'Final sequence before terminal operation.',
          );
        }
      } catch (_) {
        _processed = oldPosition;
        _sequence = oldSequence;
        rethrow;
      }
      _transcript = result.transcript;
      for (final event in parsed) {
        _events.add(event);
      }
      _tracking = result.trackingState;
      _events.add(TilawaTrackingStateObserved(_context(), _tracking));
      return result;
    } catch (error) {
      final failure = error is TilawaException
          ? error
          : TilawaException(
              error is TimeoutException
                  ? 'operationTimeout'
                  : 'inferenceFailed',
              '$error',
              operationId: id,
            );
      _quarantined = true;
      if (incompleteOnFailure) {
        _fatal ??= failure;
      } else {
        _fail(failure);
      }
      throw failure;
    } finally {
      _batch = null;
    }
  }

  Future<TilawaFeedReceipt> feed(Float32List pcm) {
    try {
      _usable();
      if (_state != TilawaLifecycle.ready &&
          _state != TilawaLifecycle.accepting) {
        throw const TilawaException(
          'invalidState',
          'Reset before feeding a closed run.',
        );
      }
      if (pcm.isEmpty ||
          pcm.length > _config.maxChunkSamples ||
          pcm.any((value) => !value.isFinite || value < -1 || value > 1)) {
        throw const TilawaException(
          'invalidAudio',
          'Expected finite normalized mono 16 kHz float32 PCM within chunk limit.',
        );
      }
      if (_reserved + pcm.length > _config.maxOutstandingSamples) {
        throw const TilawaException(
          'audioOverrun',
          'Outstanding audio capacity exceeded; chunk was not accepted.',
        );
      }
      final copy = Float32List.fromList(pcm);
      final start = _submitted;
      _submitted += copy.length;
      _reserved += copy.length;
      if (_state == TilawaLifecycle.ready) _stateTo(TilawaLifecycle.accepting);
      return _enqueue(() async {
        final result = await _engine(
          () => _adapter.feed(copy),
          expectedSamples: start + copy.length,
        );
        return TilawaFeedReceipt(
          start,
          start + copy.length,
          result.consumedSamples,
        );
      }).whenComplete(() => _reserved -= copy.length);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Future<TilawaSessionResult> stop() => _end(null);
  Future<TilawaSessionResult> interrupt(TilawaInterruption reason) =>
      _end(reason);
  Future<TilawaSessionResult> _end(TilawaInterruption? reason) {
    try {
      if (_state == TilawaLifecycle.disposed ||
          _state == TilawaLifecycle.disposing) {
        throw const TilawaException('disposed', 'Session is closing.');
      }
      if (_resetting != null) {
        throw const TilawaException(
          'invalidState',
          'Await reset before ending a new run.',
        );
      }
      if (_ending != null) return _ending!;
      _usable();
      final interrupted = reason != null;
      _stateTo(
        interrupted ? TilawaLifecycle.interrupting : TilawaLifecycle.stopping,
      );
      // Deadline includes queued accepted work, not just stop's inference tail.
      final terminalClock = Stopwatch()..start();
      Future<TilawaSessionResult> finish() async {
        if (_lastResult != null) return _lastResult!;
        if (_state == TilawaLifecycle.disposed) {
          throw const TilawaException(
            'disposed',
            'Session closed before finalization.',
          );
        }
        final warnings = <TilawaException>[];
        TilawaEngineSnapshot? result;
        try {
          final remaining = interrupted
              ? _config.interruptionDeadline - terminalClock.elapsed
              : null;
          if (remaining != null && remaining <= Duration.zero) {
            throw const TilawaException(
              'operationTimeout',
              'Interruption deadline expired.',
            );
          }
          result = await _engine(
            _adapter.stop,
            timeout: remaining,
            expectedSamples: _submitted,
            finalizing: true,
            incompleteOnFailure: interrupted,
          );
          if (result.sequence == null ||
              result.score == null ||
              !result.score!.isFinite) {
            throw const TilawaException(
              'invalidEngineOutput',
              'Final sequence missing from completed flush.',
            );
          }
        } catch (error) {
          if (_lastResult != null) return _lastResult!;
          if (_state == TilawaLifecycle.disposed) rethrow;
          result = null;
          if (!interrupted) {
            final failure = error is TilawaException
                ? error
                : TilawaException('inferenceFailed', '$error');
            _quarantined = true;
            _fail(failure);
            throw failure;
          }
          final warning = error is TilawaException
              ? error
              : TilawaException('incompleteFinalization', '$error');
          warnings.add(warning);
          _quarantined = true;
          _fatal ??= warning;
          _events.add(TilawaWarning(_context(), warning));
        }
        final completed = TilawaSessionResult(
          sessionId: _sessionId,
          runId: _runId,
          endReason: interrupted
              ? TilawaEndReason.interruption
              : TilawaEndReason.stop,
          finalization: result == null
              ? TilawaFinalization.incomplete
              : TilawaFinalization.complete,
          engineSequence: result?.sequence,
          sequenceScore: result?.score,
          transcript: _transcript,
          representation: info.capabilities.transcriptRepresentation,
          submittedSamples: _submitted,
          processedSamples: _processed,
          interruption: reason,
          warnings: warnings,
        );
        _lastResult = completed;
        if (_state != TilawaLifecycle.disposing) {
          _stateTo(
            interrupted ? TilawaLifecycle.interrupted : TilawaLifecycle.stopped,
          );
        }
        _events.add(TilawaSessionEnded(_context(), completed));
        return completed;
      }

      final queued = _enqueue(finish);
      // If earlier work stalls, fence the runtime instead of waiting forever.
      _ending = interrupted
          ? queued.timeout(
              _config.interruptionDeadline,
              onTimeout: () {
                _quarantined = true;
                const warning = TilawaException(
                  'operationTimeout',
                  'Interruption could not drain in time.',
                );
                if (_state == TilawaLifecycle.disposed) throw warning;
                _fatal ??= warning;
                final result = TilawaSessionResult(
                  sessionId: _sessionId,
                  runId: _runId,
                  endReason: TilawaEndReason.interruption,
                  finalization: TilawaFinalization.incomplete,
                  engineSequence: null,
                  transcript: _transcript,
                  representation: info.capabilities.transcriptRepresentation,
                  submittedSamples: _submitted,
                  processedSamples: _processed,
                  interruption: reason,
                  warnings: [warning],
                );
                _lastResult = result;
                _events.add(TilawaWarning(_context(), warning));
                if (_state != TilawaLifecycle.disposing) {
                  _stateTo(TilawaLifecycle.interrupted);
                }
                _events.add(TilawaSessionEnded(_context(), result));
                return result;
              },
            )
          : queued;
      return _ending!;
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Future<void> reset() {
    try {
      _usable();
      if (_state == TilawaLifecycle.disposing) {
        throw const TilawaException('disposed', 'Session is closing.');
      }
      if (_resetting != null) return _resetting!;
      final end = _ending;
      _stateTo(TilawaLifecycle.resetting);
      final pending = _enqueue(() async {
        if (end != null) await end;
        _usable();
        _batch = [];
        try {
          final result = await _adapter.reset();
          _usable();
          if (result.consumedSamples != 0 ||
              result.transcript.isNotEmpty ||
              _batch!.isNotEmpty) {
            throw const TilawaException(
              'invalidEngineOutput',
              'Reset must clear engine state without recognition output.',
            );
          }
          _submitted = _processed = 0;
          _transcript = '';
          _lastResult = null;
          _runId = newTilawaId();
          _ending = null;
          _tracking = result.trackingState;
          if (_state != TilawaLifecycle.disposing) {
            _stateTo(TilawaLifecycle.ready);
          }
        } catch (error) {
          final failure = error is TilawaException
              ? error
              : TilawaException('inferenceFailed', '$error');
          _quarantined = true;
          _fail(failure);
          throw failure;
        } finally {
          _batch = null;
        }
      });
      _resetting = pending.whenComplete(() => _resetting = null);
      return _resetting!;
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  Future<TilawaAyahMetadata?> resolveMetadata(TilawaAyahRef ayah) async {
    _usable();
    if (_state == TilawaLifecycle.disposing) {
      throw const TilawaException('disposed', 'Session is closing.');
    }
    final resolver = _resolver;
    if (resolver == null) return null;
    final run = _runId;
    try {
      if (_metadataBindingError != null) throw _metadataBindingError!;
      final bound = _metadataDescriptor!;
      bool compatible(TilawaMetadataDescriptor descriptor) =>
          descriptor.corpusSha256 == info.corpusSha256 &&
          descriptor.segmentationId == info.segmentationId &&
          descriptor.version == bound.version &&
          descriptor.edition == bound.edition &&
          descriptor.version.trim().isNotEmpty &&
          descriptor.edition.trim().isNotEmpty;
      if (!compatible(resolver.descriptor)) {
        throw const TilawaException(
          'metadataMismatch',
          'Metadata identity differs from the bound corpus, segmentation or edition/version.',
        );
      }
      final count = await _enqueue(() {
        _usable();
        return _adapter.describeAyah(ayah);
      });
      final result = await resolver.resolveAyah(ayah);
      _usable();
      if (result == null) return null;
      final indices = result.words.map((word) => word.indexInAyah).toSet();
      if (result.ayah != ayah ||
          count <= 0 ||
          !compatible(result.descriptor) ||
          result.recognitionWordCount != count ||
          (result.ayahOnly
              ? result.words.isNotEmpty
              : indices.length != count ||
                    result.words.length != count ||
                    indices.any((index) => index < 0 || index >= count)) ||
          result.words.any(
            (word) =>
                word.displayWordIds.any((id) => id.trim().isEmpty) ||
                word.displayWordIds.toSet().length !=
                    word.displayWordIds.length ||
                (word.displayWordIds.isEmpty &&
                    word.pages.isEmpty &&
                    word.juz.isEmpty),
          ) ||
          [
            ...result.pages,
            ...result.juz,
            ...result.words.expand((word) => [...word.pages, ...word.juz]),
          ].any((value) => value <= 0)) {
        throw const TilawaException(
          'metadataMismatch',
          'Metadata ayah/word mapping is incompatible.',
        );
      }
      return result;
    } catch (error) {
      final failure = error is TilawaException
          ? error
          : TilawaException('metadataResolutionFailed', '$error');
      if (_state != TilawaLifecycle.disposed && run == _runId) {
        _events.add(TilawaWarning(_context(), failure));
      }
      throw failure;
    }
  }

  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    if (_state == TilawaLifecycle.disposed) return Future.value();
    _stateTo(TilawaLifecycle.disposing);
    _disposing = (() async {
      TilawaException? error;
      final deadlineClock = Stopwatch()..start();
      Duration remaining() {
        final budget = _config.disposalDeadline - deadlineClock.elapsed;
        return budget.isNegative ? Duration.zero : budget;
      }

      try {
        final capture = captureBindings[this];
        captureBindings[this] = null;
        if (capture != null) {
          try {
            await capture().timeout(remaining());
          } catch (failure) {
            error = TilawaException(
              'disposalFailed',
              'Capture cleanup: $failure',
            );
          }
        }
        try {
          await _queue.timeout(remaining());
        } on TimeoutException {
          _quarantined = true;
        }
        final cleanup = _adapter.dispose();
        // Keep installations leased until actual adapter cleanup succeeds,
        // even if the bounded disposal Future times out.
        unawaited(
          cleanup.then(
            (_) => _assets.release(),
            onError: (Object _, StackTrace __) {},
          ),
        );
        await cleanup.timeout(remaining());
      } catch (failure) {
        error = TilawaException('disposalFailed', '$failure');
      } finally {
        _quarantined = true;
        _stateTo(TilawaLifecycle.disposed);
        // Paused consumer subscriptions must not keep the disposal Future open.
        unawaited(_events.close());
        _clock.stop();
      }
      if (error != null) throw error;
    })();
    return _disposing!;
  }

  Future<void> _validateReferences(List<Map<String, Object?>> batch) async {
    final refs = <Map>[];
    for (final observation in batch) {
      switch (observation['type']) {
        case 'word_progress':
        case 'verse_match':
          refs.add(observation);
          if (observation['type'] == 'verse_match' &&
              observation['surrounding_verses'] is List) {
            refs.addAll(
              (observation['surrounding_verses'] as List).whereType<Map>(),
            );
          }
        case 'verse_candidate':
          if (observation['candidates'] is List) {
            refs.addAll((observation['candidates'] as List).whereType<Map>());
          }
        case 'final_sequence':
          if (observation['verses'] is List) {
            refs.addAll((observation['verses'] as List).whereType<Map>());
          }
      }
    }
    for (final value in refs) {
      if (value['surah'] is! int || value['ayah'] is! int) {
        continue; // Parser rejects malformed types.
      }
      final ref = TilawaAyahRef(value['surah'] as int, value['ayah'] as int);
      if (!_wordCounts.containsKey(ref)) {
        final count = await _adapter.describeAyah(ref);
        if (count <= 0) {
          throw const TilawaException(
            'invalidEngineOutput',
            'Ayah missing from corpus.',
          );
        }
        _wordCounts[ref] = count;
      }
      if (value['ayah_end'] is int) {
        final end = TilawaAyahRef(ref.surah, value['ayah_end'] as int);
        if (!_wordCounts.containsKey(end)) {
          _wordCounts[end] = await _adapter.describeAyah(end);
        }
      }
    }
  }

  TilawaEvent? _parse(Map<String, Object?> data) {
    int integer(Object? value) {
      if (value is! int) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Expected integer field.',
        );
      }
      return value;
    }

    double score(Object? value) {
      if (value is! num || !value.isFinite) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Expected finite score.',
        );
      }
      return value.toDouble();
    }

    String text(Object? value) {
      if (value is! String) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Expected string field.',
        );
      }
      return value;
    }

    bool flag(Object? value) {
      if (value is! bool) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Expected boolean field.',
        );
      }
      return value;
    }

    TilawaAyahRef ayah(Map value) {
      final ref = TilawaAyahRef(
        integer(value['surah']),
        integer(value['ayah']),
      );
      if (ref.surah < 1 ||
          ref.surah > 114 ||
          ref.ayah < 1 ||
          !_wordCounts.containsKey(ref)) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Invalid ayah reference.',
        );
      }
      return ref;
    }

    List items(Object? value) {
      if (value is! List) {
        throw const TilawaException(
          'invalidEngineOutput',
          'Expected array field.',
        );
      }
      return value;
    }

    final kind = text(data['type']);
    if (kind == 'debug' && !_config.diagnostics) return null;
    final context = _context();
    switch (kind) {
      case 'verse_candidate':
        return TilawaVerseCandidates(
          context,
          items(data['candidates']).map((item) {
            final candidate = item as Map;
            final ref = ayah(candidate);
            final end = candidate['ayah_end'] == null
                ? null
                : integer(candidate['ayah_end']);
            if (end != null &&
                (end < ref.ayah ||
                    (_wordCounts[TilawaAyahRef(ref.surah, end)] ?? 0) <= 0)) {
              throw const TilawaException(
                'invalidEngineOutput',
                'Invalid candidate range.',
              );
            }
            return TilawaCandidate(
              ayah: ref,
              ayahEnd: end,
              score: score(candidate['confidence']),
              rank: integer(candidate['rank']),
              source: text(candidate['source']),
            );
          }),
          stable: flag(data['stable']),
          finalFlush: flag(data['final_flush']),
        );
      case 'verse_match':
        final display = text(data['verse_text']);
        final name = text(data['surah_name']);
        return TilawaVerseMatched(
          context,
          ayah(data),
          score(data['confidence']),
          text: display.isEmpty ? null : display,
          surahName: name.isEmpty ? null : name,
          surrounding: items(data['surrounding_verses']).map((item) {
            final verse = item as Map;
            return TilawaSurroundingVerse(
              ayah(verse),
              text(verse['text']),
              flag(verse['is_current']),
            );
          }),
        );
      case 'word_progress':
        final count = integer(data['total_words']);
        final index = integer(data['word_index']);
        final matched = items(data['matched_indices']).map(integer).toList();
        if (count <= 0 ||
            count != _wordCounts[ayah(data)] ||
            index < 0 ||
            index >= count ||
            matched.any((word) => word < 0 || word >= count)) {
          throw const TilawaException(
            'invalidEngineOutput',
            'Word indices outside ayah.',
          );
        }
        return TilawaWordProgress(context, ayah(data), index, count, matched);
      case 'raw_transcript':
        return TilawaTranscriptUpdated(
          context,
          text(data['text']),
          score(data['confidence']),
          info.capabilities.transcriptRepresentation,
        );
      case 'final_sequence':
        return TilawaFinalSequenceObserved(
          context,
          items(data['verses']).map((item) {
            final verse = item as Map;
            return TilawaSequenceVerse(ayah(verse), score(verse['confidence']));
          }),
          score(data['confidence']),
        );
      case 'debug':
        return TilawaDiagnostic(
          context,
          text(data['event']),
          DateTime.fromMillisecondsSinceEpoch(integer(data['at']), isUtc: true),
          Map<String, Object?>.from(data['data'] as Map),
        );
      default:
        return TilawaUnknownObservation(context, kind, data);
    }
  }
}
