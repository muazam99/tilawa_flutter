// Private recorded-input test. No microphone or consumer UI; never published.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';

Future<void> runCorrectionReplay(
  TilawaPreparedAssets assets,
  void Function(String label, Map<String, Object?> data) log,
  Future<void> Function() requireForeground,
) async {
  final source = await rootBundle.load('assets/runtime/correction-replay.wav');
  final bytes = source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes);
  final pcm = _wav(bytes);
  if (pcm.length > 16000 * 120) throw StateError('Replay clip exceeds two minutes.');
  final evidence = <Map<String, Object?>>[];
  final sdk = await TilawaSession.open(assets: assets,
    config: const TilawaRecognitionConfig(mode: TilawaRecitationMode.correction,
      structuralCorrection: TilawaStructuralCorrection.onStop, wordEvidence: true),
  );
  final subscription = sdk.events.listen((event) {
    final context = {'samples': event.context.inputPositionSamples,
      'run': event.context.runId, 'sequence': event.context.sequence};
    if (event is TilawaCorrectionChanged) {
      final state = event.state;
      evidence.add({'type': 'correction', ...context, 'phase': state.phase.name,
        'attempt': state.attempt, 'outcome': state.outcome?.name,
        'issue': state.issue == null ? null : {
          'surah': state.issue!.position.ayah.surah,
          'ayah': state.issue!.position.ayah.ayah,
          'word': state.issue!.position.indexInAyah,
          'kind': state.issue!.kind.name, 'source': state.issue!.source,
        }});
    } else if (event is TilawaWordEvidence) {
      evidence.add({'type': 'word_evidence', ...context, 'revision': event.revision,
        'attempt': event.attempt, 'words': event.words.map((word) => {
          'surah': word.position.ayah.surah, 'ayah': word.position.ayah.ayah,
          'word': word.position.indexInAyah, 'state': word.state.name,
          'distance': word.distance, 'margin': word.margin, 'heardRatio': word.heardRatio,
          'vowelErrors': word.vowelErrors, 'vowelMargin': word.vowelMargin,
          'gop': word.gop, 'gopNone': word.gopNone, 'repGain': word.repetitionGain,
        }).toList()});
    } else if (event is TilawaFinalSequenceObserved) {
      evidence.add({'type': 'final_sequence', ...context,
        'verses': event.verses.map((verse) => '${verse.ayah}').toList()});
    } else if (event is TilawaFailure) {
      evidence.add({'type': 'failure', ...context, 'code': event.error.code});
    }
  });
  try {
    for (var at = 0; at < pcm.length; at += 7680) {
      await requireForeground();
      final end = at + 7680 > pcm.length ? pcm.length : at + 7680;
      await sdk.feed(Float32List.sublistView(pcm, at, end));
      while (sdk.snapshot.correction.phase != TilawaCorrectionPhase.idle) {
        final snapshot = sdk.snapshot;
        // Diagnostic continuation only: never call an error "corrected".
        await sdk.correct(TilawaCorrectionAction.dismiss,
          runId: snapshot.runId, attempt: snapshot.correction.attempt);
      }
    }
    final result = await sdk.stop();
    await Future<void>.delayed(Duration.zero);
    final support = await getApplicationSupportDirectory();
    final path = '${support.path}/correction-replay-${DateTime.now().microsecondsSinceEpoch}.json';
    await File(path).writeAsString(jsonEncode({
      'clipSha256': sha256.convert(bytes).toString(), 'samples': pcm.length,
      'adapter': sdk.info.adapterId, 'adapterVersion': sdk.info.adapterVersion,
      'upstreamCommit': sdk.info.upstreamCommit, 'expectedPassage': null,
      'policy': 'Log each issue, then dismiss after the feed so all audio can be compared.',
      'finalization': result.finalization.name, 'events': evidence,
      'accuracy': 'Not computed. Requires actual spoken-error annotations.',
    }), flush: true);
    log('CORRECTION_REPLAY_SAVED', {'path': path, 'samples': pcm.length,
      'adapter': sdk.info.adapterId, 'events': evidence.length});
  } finally {
    await sdk.dispose();
    await subscription.cancel();
  }
}

Float32List _wav(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  String tag(int offset) => String.fromCharCodes(bytes.sublist(offset, offset + 4));
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw StateError('Expected PCM16 mono16k WAV.');
  }
  var valid = false;
  Uint8List? audio;
  for (var offset = 12; offset + 8 <= bytes.length;) {
    final size = view.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + size > bytes.length) throw StateError('Truncated WAV.');
    if (tag(offset) == 'fmt ' && size >= 16) {
      valid = view.getUint16(start, Endian.little) == 1 &&
          view.getUint16(start + 2, Endian.little) == 1 &&
          view.getUint32(start + 4, Endian.little) == 16000 &&
          view.getUint16(start + 14, Endian.little) == 16;
    }
    if (tag(offset) == 'data') audio = Uint8List.sublistView(bytes, start, start + size);
    offset = start + size + (size % 2);
  }
  if (!valid || audio == null || audio.length.isOdd) throw StateError('Use PCM16 mono16k WAV.');
  final input = ByteData.sublistView(audio);
  return Float32List.fromList(List.generate(audio.length ~/ 2,
    (index) => input.getInt16(index * 2, Endian.little) / 32768));
}
