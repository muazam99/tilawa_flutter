// Phase 4 private public-SDK consumer. Phase 5 standalone example is separate.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/microphone.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

import 'asset_probe.dart';
import 'audio_fixture.dart';
import 'metadata_fixture.dart';
import 'tracking_contract_probe.dart';
import 'tracking_presentation.dart';

void main() => runApp(const MaterialApp(home: _TrackingProbe()));

class _TrackingProbe extends StatefulWidget {
  const _TrackingProbe();
  @override
  State<_TrackingProbe> createState() => _TrackingProbeState();
}

class _TrackingProbeState extends State<_TrackingProbe> {
  TilawaSession? _session;
  TilawaMicrophone? _microphone;
  FixtureMetadata? _fixture;
  final _view = TrackingPresentation();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _lines = <String>[];
  final _diagnostics = <String, int>{};
  final _previousProgress = <TilawaAyahRef, String>{};
  int _matches = 0, _progress = 0, _duplicates = 0, _metadataLoads = 0;
  bool _busy = false, _closing = false;
  String? _error;

  void _log(String message) {
    debugPrint('TILAWA_TRACK $message');
    if (mounted) setState(() => _lines.add(message));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_action(_initialize));
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy || _closing) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error, stack) {
      _log('ERROR $error');
      if (mounted) setState(() => _error = '$error');
      debugPrint('$stack');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _initialize() async {
    final support = await getApplicationSupportDirectory();
    final store = TilawaAssetStore(
      Directory('${support.path}/tilawa-sdk-assets'),
    );
    final manifest = TilawaAssetManifest.zipformerV1();
    final assets = await store.fromBundled(manifest, {
      for (final file in manifest.files)
        file.name: 'assets/runtime/${file.name}',
    }).completed;
    _fixture = await FixtureMetadata.load();
    if (const bool.fromEnvironment('PROBE_TRACK_CONTRACT')) {
      await runTrackingContractProbe(assets, _fixture!, _log);
    }
    _session = await TilawaSession.open(
      assets: assets,
      metadataResolver: _fixture,
      config: const TilawaRecognitionConfig(diagnostics: true),
    );
    _subscriptions.add(_session!.events.listen(_observe));
    // Validate every developer fixture row against the real adapter corpus.
    var words = 0;
    for (final ayah in _fixture!.ayahs.keys) {
      final metadata = await _session!.resolveMetadata(ayah);
      requireAssetProbe(metadata != null, 'Fixture ayah was not resolvable');
      words += metadata!.words.length;
    }
    _log(
      'REAL_METADATA ayahs=${_fixture!.ayahs.length} words=$words pages=604 juz=30',
    );
    _log('READY noAutomaticMicrophone=true');
    if (const bool.fromEnvironment('PROBE_TRACK_AUTORUN')) await _replay();
  }

  void _observe(TilawaEvent event) {
    if (_closing || !mounted) return;
    final previousRun = _view.runId;
    final previousAyah = _view.ayah;
    _view.accept(event);
    if (previousRun != _view.runId) {
      _matches = _progress = _duplicates = 0;
      _diagnostics.clear();
      _previousProgress.clear();
    }
    if (event is TilawaVerseMatched) _matches++;
    if (event is TilawaWordProgress) {
      _progress++;
      final snapshot = '${event.wordIndex}:${event.matchedIndices.join(',')}';
      if (_previousProgress[event.ayah] == snapshot) _duplicates++;
      _previousProgress[event.ayah] = snapshot;
    }
    if (event is TilawaDiagnostic) {
      _diagnostics.update(event.name, (value) => value + 1, ifAbsent: () => 1);
    }
    if (event is TilawaWarning) _log('WARNING ${event.error.code}');
    if (event is TilawaFailure) _log('FAILURE ${event.error.code}');
    if ((previousRun != _view.runId || previousAyah != _view.ayah) &&
        _view.ayah != null) {
      unawaited(
        _resolveDisplay(_view.ayah!, _view.runId!, _view.metadataGeneration),
      );
    }
    setState(() {});
  }

  Future<void> _resolveDisplay(
    TilawaAyahRef ayah,
    String run,
    int generation,
  ) async {
    try {
      final metadata = await _session!.resolveMetadata(ayah);
      if (!_closing &&
          mounted &&
          _view.applyMetadata(
            metadata,
            requestedRun: run,
            generation: generation,
            requestedAyah: ayah,
          )) {
        _metadataLoads++;
        setState(() {});
      }
    } catch (error) {
      if (!_closing) _log('DISPLAY_UNAVAILABLE $error');
    }
  }

  Future<void> _feed(Float32List pcm) async {
    for (var offset = 0; offset < pcm.length; offset += 7680) {
      await _session!.feed(
        Float32List.sublistView(pcm, offset, min(offset + 7680, pcm.length)),
      );
    }
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _reset() async {
    await _microphone?.stopCapture();
    await _session!.reset();
    await Future<void>.delayed(Duration.zero);
    _log(
      'RESET newRun=true displayCleared=${_view.progress == null && _view.metadata == null}',
    );
  }

  Future<void> _replay() async {
    await _reset();
    final multi = await decodeAudioFixture(
      await rootBundle.load('assets/runtime/multi_113_001_005.audio'),
    );
    await _feed(multi);
    final firstMatches = _matches, firstProgress = _progress;
    _log('PASS1 matches=$firstMatches progress=$firstProgress');
    requireAssetProbe(
      firstMatches == 5 && firstProgress > 0,
      'First replay did not track expected passage',
    );
    await _feed(Float32List(64000));
    await _feed(multi);
    _log(
      'PASS2 newMatches=${_matches - firstMatches} newProgress=${_progress - firstProgress} '
      'duplicateSnapshots=$_duplicates',
    );
    requireAssetProbe(
      _progress > firstProgress,
      'Repeated audio produced no tracking observations',
    );
    // A separate known recording changes surah in this same run.
    await _feed(Float32List(64000));
    final single = await decodeAudioFixture(
      await rootBundle.load('assets/runtime/ref_112001.audio'),
    );
    await _feed(single);
    final result = await _session!.stop();
    await Future<void>.delayed(Duration.zero);
    requireAssetProbe(
      identical(result, _view.result) &&
          identical(result, await _session!.stop()),
      'Canonical completion identity changed',
    );
    final refs = result.engineSequence!
        .map((verse) => verse.ayah.toString())
        .toList();
    requireAssetProbe(
      refs.toSet().length == refs.length &&
          refs.join(',') == '113:1,113:2,113:3,113:4,113:5,112:1',
      'Repeated/changed-passage final sequence differs: $refs',
    );
    _log(
      'REAL_RESULT ${refs.join(',')} matches=$_matches progress=$_progress '
      'samples=${result.processedSamples} canonical=true',
    );
    _log('REAL_DIAGNOSTICS $_diagnostics metadataLoads=$_metadataLoads');
    _log('TRACK_REPLAY_COMPLETE');
  }

  Future<void> _startMicrophone() async {
    await _reset();
    if (_microphone == null) {
      _microphone = await TilawaMicrophone.open(session: _session!);
      _subscriptions.add(
        _microphone!.errors.listen((error) => _log('MIC_ERROR ${error.code}')),
      );
    }
    await _microphone!.start();
    _log('MIC_STARTED localOnly=true');
  }

  Future<void> _stopMicrophone() async {
    await _microphone!.stopCapture();
    final result = await _session!.stop();
    _log(
      'MIC_STOP verses=${result.engineSequence?.length} samples=${result.processedSamples}',
    );
  }

  Future<void> _close() async {
    _closing = true;
    await _session?.dispose();
    _log('DISPOSED helper=${_microphone?.state.name ?? 'notStarted'}');
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_session?.dispose());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _view.metadata;
    final progress = _view.progress;
    final matched = progress?.matchedIndices.toSet() ?? <int>{};
    return Scaffold(
      appBar: AppBar(title: const Text('Tilawa tracking + metadata')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Private developer fixture: surahs 112/113. '
            'Page/juz references describe the layout, not completed reading.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final control in <(String, Future<void> Function())>[
                ('Replay twice + change', _replay),
                ('Reset', _reset),
                ('Start mic', _startMicrophone),
                ('Stop mic', _stopMicrophone),
                ('Dispose', _close),
              ])
                ElevatedButton(
                  onPressed: _busy || _closing || _session == null
                      ? null
                      : () => _action(control.$2),
                  child: Text(control.$1),
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          Text(
            'Lifecycle: ${_view.lifecycle.name} | sampled tracking: ${_view.tracking.name}',
          ),
          if (_view.lostDiagnostic)
            const Text(
              'Lost diagnostic observed. Last snapshot retained; '
              'this is not a complete tracking-transition stream.',
            ),
          Text(
            'Latest candidate: ${_view.candidates.map((candidate) => candidate.ayah).join(', ')}',
          ),
          Text(
            'Tracked ayah: ${_view.ayah ?? 'Waiting for recognition'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (metadata != null) ...[
            Text(
              'Page references: ${metadata.pages.join(', ')} | Juz: ${metadata.juz.join(', ')}',
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: metadata.words
                    .map(
                      (word) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: matched.contains(word.indexInAyah)
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: progress?.wordIndex == word.indexInAyah
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(
                          word.displayWordIds
                              .map(
                                (id) =>
                                    _fixture!.labels[id] ??
                                    '[unmapped display ID]',
                              )
                              .join(' '),
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ] else if (_view.ayah != null)
            const Text(
              'No validated display mapping yet. Recognition remains usable.',
            ),
          const SizedBox(height: 8),
          Text(
            'Latest snapshot: cursor=${progress?.wordIndex ?? '-'} (0-based), '
            'indices=${progress?.matchedIndices ?? []}',
          ),
          const Text(
            'Tint = tracker ok/unsure snapshot, not certified correct words. '
            'Border = cursor, not proof of all preceding words. Revisions replace highlights.',
          ),
          const SizedBox(height: 8),
          Text(
            'Observation counts only: matches=$_matches, progress=$_progress, duplicates=$_duplicates',
          ),
          if (_view.result != null)
            Text(
              'Final engine sequence: '
              '${_view.result!.engineSequence?.map((verse) => verse.ayah).join(', ')}\n'
              'Not a chronological history of every repeated reading.',
            ),
          const Divider(),
          ..._lines.reversed
              .take(12)
              .map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, style: const TextStyle(fontSize: 12)),
                ),
              ),
        ],
      ),
    );
  }
}
