import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_controller.dart';

class RecitationDemo extends StatefulWidget {
  const RecitationDemo({super.key});

  @override
  State<RecitationDemo> createState() => _RecitationDemoState();
}

class _RecitationDemoState extends State<RecitationDemo> {
  final controller = DemoController();

  @override
  void initState() {
    super.initState();
    unawaited(controller.checkLocal());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _license() async {
    final text = await rootBundle.loadString(
      'packages/tilawa_flutter/assets/runtime/NPL-1.2.txt',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quran-Lab NPL-1.2'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final colors = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final download = c.downloadProgress;
      final metadata = c.metadata;
      final progress = c.progress;
      final matched = progress?.matchedIndices.toSet() ?? <int>{};
      return Scaffold(
        appBar: AppBar(title: const Text('Tilawa developer example')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Find and follow recitation', style: text.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Offline recognition after setup. Foreground microphone only. '
                    'This independent SDK is still a development release.',
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    title: '1. Assets and runtime',
                    children: [
                      Text(c.status),
                      if (c.busy) ...[
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: c.downloading && download != null
                              ? download.receivedBytes / download.expectedBytes
                              : null,
                          semanticsLabel: c.status,
                        ),
                      ],
                      if (c.downloading) ...[
                        const SizedBox(height: 8),
                        if (download != null)
                          Text(
                            '${download.file}: ${download.receivedBytes} / '
                            '${download.expectedBytes} bytes, attempt ${download.attempt}',
                          ),
                        TextButton(
                          onPressed: c.cancelling ? null : c.cancelDownload,
                          child: Text(
                            c.cancelling ? 'Cancelling...' : 'Cancel download',
                          ),
                        ),
                      ],
                      if (c.error != null) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            c.error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: c.canSetup ? c.checkLocal : null,
                            child: const Text('Check / reopen local'),
                          ),
                          OutlinedButton(
                            onPressed: c.canSetup ? c.download : null,
                            child: const Text('Download / retry'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Model, corpus and I/O: 74.7 MB download. NPL-1.2 '
                        'prohibits charging or advertising on powered features. '
                        'Downloaded assets and this small display fixture retain its terms.',
                      ),
                      TextButton(
                        onPressed: _license,
                        child: const Text('Read full asset license'),
                      ),
                    ],
                  ),
                  _Section(
                    title: '2. Recognition',
                    children: [
                      Text(
                        'Session: ${c.lifecycle?.name ?? 'not open'} | '
                        'microphone: ${c.captureState.name}',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: c.canStart ? c.startMicrophone : null,
                            icon: const Icon(Icons.mic_outlined),
                            label: const Text('Start microphone'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: c.canStop ? c.stopMicrophone : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                          OutlinedButton(
                            onPressed: c.canReset ? c.reset : null,
                            child: const Text('Reset'),
                          ),
                          OutlinedButton(
                            onPressed: c.canRelease ? c.releaseSession : null,
                            child: const Text('Dispose session'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Sampled tracking: ${c.tracking.name}'),
                      Text(
                        'Candidates: ${c.candidates.isEmpty ? 'none yet' : c.candidates.map((v) => '${v.ayah} (score ${v.score.toStringAsFixed(3)})').join(', ')}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tracked ayah: ${c.ayah ?? 'waiting'}',
                        style: text.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (metadata != null) ...[
                        Text(
                          'Page references: ${metadata.pages.join(', ')} | '
                          'juz: ${metadata.juz.join(', ')}',
                        ),
                        const SizedBox(height: 12),
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final word in metadata.words)
                                Semantics(
                                  label:
                                      '${word.displayWordIds.map((id) => c.fixture!.labels[id] ?? '[unmapped]').join(' ')}. '
                                      'Index ${word.indexInAyah}, '
                                      '${matched.contains(word.indexInAyah) ? 'tracker evidence present' : 'no tracker evidence'}'
                                      '${progress?.wordIndex == word.indexInAyah ? ', current cursor' : ''}',
                                  child: ExcludeSemantics(
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color:
                                            matched.contains(word.indexInAyah)
                                            ? colors.primaryContainer
                                            : colors.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          width: 2,
                                          color:
                                              progress?.wordIndex ==
                                                  word.indexInAyah
                                              ? colors.primary
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Text(
                                        word.displayWordIds
                                            .map(
                                              (id) =>
                                                  c.fixture!.labels[id] ??
                                                  '[unmapped]',
                                            )
                                            .join(' '),
                                        style: text.headlineSmall?.copyWith(
                                          color:
                                              matched.contains(word.indexInAyah)
                                              ? colors.onPrimaryContainer
                                              : colors.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ] else if (c.ayah != null)
                        Text(
                          c.metadataLoading
                              ? 'Checking display mapping...'
                              : 'Display metadata unavailable. This fixture covers only112/113. '
                                    'References and recognition indices remain available.',
                        ),
                      if (c.metadataError != null)
                        Text('Mapping rejected: ${c.metadataError}'),
                      const SizedBox(height: 12),
                      Text(
                        'Cursor: ${progress?.wordIndex ?? '-'} (0-based). '
                        'Latest indices: ${progress?.matchedIndices ?? []}',
                      ),
                      const Text(
                        'Tint = tracker ok/unsure evidence. Border = cursor. '
                        'Revisions replace highlights; neither certifies correctness or completion.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Recognition corpus:114 surahs. Display:9 ayahs/38 words in112/113. '
                        'Page604/juz30 annotations are layout references, not pages read.',
                      ),
                    ],
                  ),
                  _Section(
                    title: '3. Observations and final result',
                    children: [
                      Text(
                        'This run: ${c.verseObservations} verse-match events, '
                        '${c.progressObservations} progress events.',
                      ),
                      const Text(
                        'Example-owned observation counts only. No repeat credit, '
                        'reading minutes or page-completion policy.',
                      ),
                      if (c.result != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'End: ${c.result!.endReason.name}. '
                          'Finalization: ${c.result!.finalization.name}.',
                        ),
                        Text(
                          'Processed / submitted samples: ${c.result!.processedSamples} / '
                          '${c.result!.submittedSamples}',
                        ),
                        Text(
                          'Final engine sequence: ${c.result!.engineSequence == null
                              ? 'not supplied'
                              : c.result!.engineSequence!.isEmpty
                              ? 'empty'
                              : c.result!.engineSequence!.map((v) => '${v.ayah} (${v.score.toStringAsFixed(3)})').join(', ')}',
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Scores are uncalibrated engine values, not probabilities. '
                        'Final sequences suppress some repeats; they are not a full reading history.',
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Latest transcript (${c.representation.name})',
                        ),
                        children: [
                          SelectableText(
                            c.transcript.isEmpty
                                ? 'No transcript yet.'
                                : c.transcript,
                          ),
                        ],
                      ),
                      if (c.notices.isNotEmpty) ...[
                        const Text(
                          'Warnings and recovery',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        for (final notice in c.notices)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(notice),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}
