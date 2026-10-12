// Private developer-supplied metadata. Not a default SDK Quran edition.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

final class FixtureMetadata implements TilawaMetadataResolver {
  FixtureMetadata._(this.descriptor, this.ayahs, this.labels);
  @override
  final TilawaMetadataDescriptor descriptor;
  final Map<TilawaAyahRef, TilawaAyahMetadata> ayahs;
  final Map<String, String> labels;

  static Future<FixtureMetadata> load() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/tracking_fixture.json'))
            as Map;
    final identity = data['descriptor'] as Map;
    final descriptor = TilawaMetadataDescriptor(
      version: identity['version'] as String,
      edition: identity['edition'] as String,
      corpusSha256: identity['corpusSha256'] as String,
      segmentationId: identity['segmentationId'] as String,
    );
    final ayahs = <TilawaAyahRef, TilawaAyahMetadata>{};
    final labels = <String, String>{};
    for (final raw in data['ayahs'] as List) {
      final ayah = TilawaAyahRef(raw['surah'] as int, raw['ayah'] as int);
      final words = raw['words'] as List;
      final mappings = <TilawaWordMetadata>[];
      for (final word in words) {
        final id = word['id'] as String;
        if (labels.containsKey(id)) {
          throw StateError('Duplicate fixture display ID');
        }
        labels[id] = word['text'] as String;
        mappings.add(
          TilawaWordMetadata(
            word['index'] as int,
            displayWordIds: [id],
            pages: (word['pages'] as List).cast<int>(),
            juz: (word['juz'] as List).cast<int>(),
          ),
        );
      }
      ayahs[ayah] = TilawaAyahMetadata(
        ayah: ayah,
        descriptor: descriptor,
        recognitionWordCount: words.length,
        words: mappings,
        text: words.map((word) => word['text'] as String).join(' '),
        pages: (raw['pages'] as List).cast<int>(),
        juz: (raw['juz'] as List).cast<int>(),
      );
    }
    return FixtureMetadata._(
      descriptor,
      Map.unmodifiable(ayahs),
      Map.unmodifiable(labels),
    );
  }

  @override
  Future<TilawaAyahMetadata?> resolveAyah(TilawaAyahRef ayah) async =>
      ayahs[ayah];
}
