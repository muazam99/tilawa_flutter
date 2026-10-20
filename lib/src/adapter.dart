import 'dart:typed_data';

import 'assets.dart';
import 'models.dart';

typedef TilawaObservationSink = void Function(Map<String, Object?> observation);

final class TilawaEngineSnapshot {
  TilawaEngineSnapshot({
    required this.consumedSamples,
    required this.trackingState,
    required this.transcript,
    Iterable<TilawaSequenceVerse>? sequence,
    this.score,
    this.correction,
  }) : sequence = sequence == null ? null : List.unmodifiable(sequence);
  final int consumedSamples;
  final TilawaTrackingState trackingState;
  final String transcript;
  final List<TilawaSequenceVerse>? sequence;
  final double? score;
  final TilawaCorrectionState? correction;
}

abstract interface class TilawaEngineAdapterFactory {
  Future<TilawaEngineAdapter> create(
    TilawaPreparedAssets assets,
    TilawaRecognitionConfig config,
    TilawaObservationSink observationSink,
  );
}

/// Advanced seam. The facade owns disposal of a factory-created adapter.
/// Callbacks must occur within the producing operation, before it completes.
abstract interface class TilawaEngineAdapter {
  String get id;
  String get version;
  TilawaCapabilities get capabilities;
  Future<TilawaEngineSnapshot> feed(Float32List pcm);
  Future<TilawaEngineSnapshot> stop();
  Future<TilawaEngineSnapshot> reset();
  Future<int> describeAyah(TilawaAyahRef ayah);
  Future<void> dispose();
}

/// Optional extension. Existing tracking-only adapters need not implement it.
/// Actions reset all acoustic/recurrent state while retaining model resources.
abstract interface class TilawaCorrectionAdapter {
  Future<TilawaEngineSnapshot> setExpectedPassage(
    TilawaExpectedPassage? passage,
  );
  Future<TilawaEngineSnapshot> correct(TilawaCorrectionAction action);
}
