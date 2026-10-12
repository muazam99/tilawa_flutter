import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

/// Example-owned, NPL-1.2 corpus labels. Not a default SDK display edition.
final class DemoMetadataResolver implements TilawaMetadataResolver {
  DemoMetadataResolver._(this.descriptor, this.ayahs, this.labels);

  @override
  final TilawaMetadataDescriptor descriptor;
  final Map<TilawaAyahRef, TilawaAyahMetadata> ayahs;
  final Map<String, String> labels;

  static Future<DemoMetadataResolver> load() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/demo_metadata.json'))
            as Map<String, dynamic>;
    final identity = data['descriptor'] as Map<String, dynamic>;
    final descriptor = TilawaMetadataDescriptor(
      version: identity['version'] as String,
      edition: identity['edition'] as String,
      corpusSha256: identity['corpusSha256'] as String,
      segmentationId: identity['segmentationId'] as String,
    );
    final ayahs = <TilawaAyahRef, TilawaAyahMetadata>{};
    final labels = <String, String>{};
    for (final row in data['ayahs'] as List<dynamic>) {
      final raw = row as Map<String, dynamic>;
      final ayah = TilawaAyahRef(raw['surah'] as int, raw['ayah'] as int);
      final words = (raw['words'] as List<dynamic>).cast<String>();
      final pages = [raw['page'] as int];
      final juz = [raw['juz'] as int];
      if (ayahs.containsKey(ayah) || words.isEmpty) {
        throw const FormatException('Duplicate or empty demo ayah.');
      }
      final mappings = <TilawaWordMetadata>[];
      for (var index = 0; index < words.length; index++) {
        // Display IDs are example-owned. SDK indices remain0-based.
        final id = '$ayah:${index + 1}';
        labels[id] = words[index];
        mappings.add(
          TilawaWordMetadata(
            index,
            displayWordIds: [id],
            pages: pages,
            juz: juz,
          ),
        );
      }
      ayahs[ayah] = TilawaAyahMetadata(
        ayah: ayah,
        descriptor: descriptor,
        recognitionWordCount: words.length,
        words: mappings,
        text: words.join(' '),
        pages: pages,
        juz: juz,
      );
    }
    return DemoMetadataResolver._(
      descriptor,
      Map.unmodifiable(ayahs),
      Map.unmodifiable(labels),
    );
  }

  @override
  Future<TilawaAyahMetadata?> resolveAyah(TilawaAyahRef ayah) async =>
      ayahs[ayah];
}
