import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

const tilawaUpstreamCommit = '2f2617460dc4a6b967e0cc49fa04804bbf22ec69';
const tilawaCorpusSha256 =
    '24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127';
// Identity describes the actual phoneme corpus's wordInAyah segmentation,
// not a Quran display edition or an independently replaceable tokenization.
const tilawaSegmentationId = 'zipformer-wordInAyah-v1:$tilawaCorpusSha256';

final class TilawaAssetFile {
  const TilawaAssetFile({
    required this.name,
    required this.bytes,
    required this.sha256,
    required this.license,
    this.downloadUri,
  });
  final String name, sha256, license;
  final int bytes;
  final Uri? downloadUri;
  Map<String, Object?> toJson() => {
    'name': name,
    'bytes': bytes,
    'sha256': sha256,
    'license': license,
    'url': downloadUri?.toString(),
  };
}

final class TilawaAssetManifest {
  TilawaAssetManifest({
    required this.id,
    required this.engineId,
    required this.engineVersion,
    required this.upstreamCommit,
    required this.segmentationId,
    required this.ioSchema,
    required Iterable<TilawaAssetFile> files,
  }) : files = List.unmodifiable(files) {
    final names = this.files.map((file) => file.name).toSet();
    if (names.length != this.files.length ||
        !names.containsAll([
          'model.onnx',
          'corpus.json',
          'io.json',
          'NPL-1.2.txt',
        ]) ||
        this.files.any(
          (file) =>
              !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(file.name) ||
              file.name == '.' ||
              file.name == '..' ||
              file.bytes <= 0 ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(file.sha256),
        )) {
      throw const TilawaException(
        'incompatibleAssets',
        'Invalid asset manifest.',
      );
    }
  }
  final String id,
      engineId,
      engineVersion,
      upstreamCommit,
      segmentationId,
      ioSchema;
  final List<TilawaAssetFile> files;
  TilawaAssetFile file(String name) =>
      files.firstWhere((file) => file.name == name);
  String get corpusSha256 => file('corpus.json').sha256;
  String get installationKey =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
  Map<String, Object?> toJson() => {
    'id': id,
    'engineId': engineId,
    'engineVersion': engineVersion,
    'upstreamCommit': upstreamCommit,
    'segmentationId': segmentationId,
    'ioSchema': ioSchema,
    'files': files.map((file) => file.toJson()).toList(),
  };

  factory TilawaAssetManifest.zipformerV1() => TilawaAssetManifest(
    id: 'zipformer-a0w-ep1-a05-core040',
    engineId: 'zipformer',
    engineVersion: '0.4.0',
    upstreamCommit: tilawaUpstreamCommit,
    segmentationId: tilawaSegmentationId,
    ioSchema: 'zipformer-a0w-ep1-a05',
    files: [
      TilawaAssetFile(
        name: 'model.onnx',
        bytes: 69246033,
        sha256:
            'bfb5b712695634a6099b45a6a78003bd5103417c4eae6338277d54679254905a',
        license: 'NPL-1.2',
        downloadUri: Uri.parse(
          'https://github.com/yazinsai/tilawa/releases/download/zipformer-a0w-ep1-a0.5/zipformer_a0w_ep1_a05.int8.onnx',
        ),
      ),
      TilawaAssetFile(
        name: 'corpus.json',
        bytes: 5453439,
        sha256: tilawaCorpusSha256,
        license: 'NPL-1.2',
        downloadUri: Uri.parse(
          'https://github.com/yazinsai/tilawa/releases/download/v0.3.0/zipformer_quran.json',
        ),
      ),
      TilawaAssetFile(
        name: 'io.json',
        bytes: 26867,
        sha256:
            '7dca1dafd6ee26044a0d3ba6b9483278203f55df7cc95d40cda865183a0d797e',
        license: 'NPL-1.2',
        downloadUri: Uri.parse(
          'https://github.com/yazinsai/tilawa/releases/download/zipformer-a0w-ep1-a0.5/zipformer_a0w_ep1_a05.io.json',
        ),
      ),
      TilawaAssetFile(
        name: 'NPL-1.2.txt',
        bytes: 7041,
        sha256:
            '77526bdbfac94132e5114c3a34492c33f915e4b7f310f00b9995500d3610cab5',
        license: 'License text',
        downloadUri: Uri.parse(
          'https://github.com/yazinsai/tilawa/releases/download/zipformer-a0w-ep1-a0.5/NPL-1.2.txt',
        ),
      ),
    ],
  );
}

final class TilawaAssetProgress {
  const TilawaAssetProgress(
    this.file,
    this.receivedBytes,
    this.expectedBytes,
    this.attempt,
  );
  final String file;
  final int receivedBytes, expectedBytes, attempt;
}

final class TilawaPreparedAssets {
  TilawaPreparedAssets._(
    this.manifest,
    Map<String, File> files,
    this.installationDirectory,
  ) : files = Map.unmodifiable(files);
  final TilawaAssetManifest manifest;
  final Map<String, File> files;
  final Directory? installationDirectory;
  static final _leases = <String, int>{};
  static final _deleting = <String>{};
  static final _installing = <String, int>{};
  static final _activeStages = <String>{};
  Future<void> verify() async {
    for (final expected in manifest.files) {
      await _verify(files[expected.name]!, expected);
    }
  }

  void retain() {
    final directory = installationDirectory;
    if (directory != null) {
      if (_deleting.contains(directory.path)) {
        throw const TilawaException(
          'assetsInUse',
          'Asset deletion is in progress.',
        );
      }
      _leases.update(directory.path, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  void release() {
    final directory = installationDirectory;
    if (directory == null) return;
    final count = _leases[directory.path] ?? 0;
    if (count <= 1) {
      _leases.remove(directory.path);
    } else {
      _leases[directory.path] = count - 1;
    }
  }
}

abstract final class TilawaAssets {
  static Future<TilawaPreparedAssets> fromLocalFiles({
    required TilawaAssetManifest manifest,
    required File model,
    required File corpus,
    required File io,
    required File license,
  }) async {
    if (manifest.files.length != 4) {
      throw const TilawaException(
        'incompatibleAssets',
        'Local entry point expects the four pinned asset files.',
      );
    }
    final prepared = TilawaPreparedAssets._(manifest, {
      'model.onnx': model,
      'corpus.json': corpus,
      'io.json': io,
      'NPL-1.2.txt': license,
    }, null);
    await prepared.verify();
    return prepared;
  }
}

final class TilawaAssetInstall {
  TilawaAssetInstall._();
  final _progress = StreamController<TilawaAssetProgress>.broadcast();
  final _result = Completer<TilawaPreparedAssets>();
  bool _cancelled = false;
  HttpClient? _client;
  Stream<TilawaAssetProgress> get progress => _progress.stream;
  Future<TilawaPreparedAssets> get completed => _result.future;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _check() {
    if (_cancelled) {
      throw const TilawaException('assetCancelled', 'Installation cancelled.');
    }
  }
}

/// Content-addressed installations. Existing versions are never overwritten.
final class TilawaAssetStore {
  TilawaAssetStore(this.directory);
  final Directory directory;

  Future<Directory> _root() async {
    await directory.create(recursive: true);
    return Directory(await directory.resolveSymbolicLinks());
  }

  Future<TilawaPreparedAssets?> available(TilawaAssetManifest manifest) async {
    final root = await _root();
    final installed = Directory(p.join(root.path, manifest.installationKey));
    if (!await installed.exists()) return null;
    final prepared = _prepared(manifest, installed);
    await prepared.verify();
    return prepared;
  }

  Future<void> delete(TilawaAssetManifest manifest) async {
    final root = await _root();
    final installed = Directory(p.join(root.path, manifest.installationKey));
    if ((TilawaPreparedAssets._leases[installed.path] ?? 0) > 0 ||
        (TilawaPreparedAssets._installing[installed.path] ?? 0) > 0) {
      throw const TilawaException(
        'assetsInUse',
        'Close sessions before deleting their installation.',
      );
    }
    if (!TilawaPreparedAssets._deleting.add(installed.path)) {
      throw const TilawaException(
        'assetsInUse',
        'Asset deletion is in progress.',
      );
    }
    try {
      if (await installed.exists()) await installed.delete(recursive: true);
    } finally {
      TilawaPreparedAssets._deleting.remove(installed.path);
    }
  }

  /// Removes stale staging directories from this dedicated store only.
  /// Active installs in this Dart isolate are retained. Cross-isolate stores
  /// need external coordination and are not supported by the initial SDK.
  Future<int> cleanupInterruptedInstallations() async {
    final root = await _root();
    var removed = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory &&
          p.basename(entry.path).startsWith('.install-') &&
          !TilawaPreparedAssets._activeStages.contains(entry.path)) {
        await entry.delete(recursive: true);
        removed++;
      }
    }
    return removed;
  }

  TilawaAssetInstall download(TilawaAssetManifest manifest, {int retries = 2}) {
    if (retries < 0 || retries > 5) {
      throw const TilawaException(
        'invalidInput',
        'Download retries must be 0..5.',
      );
    }
    return _install(manifest, (operation, expected, target) async {
      final uri = expected.downloadUri;
      if (uri == null || uri.scheme != 'https') {
        throw const TilawaException(
          'invalidInput',
          'An HTTPS download URL is required for every asset.',
        );
      }
      for (var attempt = 1; attempt <= retries + 1; attempt++) {
        operation._check();
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 30);
        operation._client = client;
        try {
          final request = await client
              .getUrl(uri)
              .timeout(const Duration(seconds: 30));
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException(
              'Asset response status ${response.statusCode}.',
            );
          }
          if (response.contentLength >= 0 &&
              response.contentLength != expected.bytes) {
            throw const TilawaException(
              'assetIntegrityMismatch',
              'Unexpected asset response length.',
            );
          }
          var received = 0;
          final sink = target.openWrite();
          try {
            await for (final chunk in response.timeout(
              const Duration(seconds: 30),
            )) {
              operation._check();
              received += chunk.length;
              if (received > expected.bytes) {
                throw const TilawaException(
                  'assetIntegrityMismatch',
                  'Asset exceeds manifest size.',
                );
              }
              sink.add(chunk);
              // Flush each network chunk to bound queued disk-write buffers.
              await sink.flush();
              operation._progress.add(
                TilawaAssetProgress(
                  expected.name,
                  received,
                  expected.bytes,
                  attempt,
                ),
              );
            }
          } finally {
            await sink.close();
          }
          operation._check();
          await _verify(target, expected);
          return;
        } catch (error) {
          operation._check();
          if (error is TilawaException || attempt > retries) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        } finally {
          client.close(force: true);
          operation._client = null;
        }
      }
    });
  }

  TilawaAssetInstall fromBundled(
    TilawaAssetManifest manifest,
    Map<String, String> assetKeys, {
    AssetBundle? bundle,
  }) => _install(manifest, (operation, expected, target) async {
    final key = assetKeys[expected.name];
    if (key == null) {
      throw const TilawaException(
        'assetMissing',
        'Missing bundled asset mapping.',
      );
    }
    operation._check();
    final bytes = await (bundle ?? rootBundle).load(key);
    operation._check();
    if (bytes.lengthInBytes != expected.bytes) {
      throw const TilawaException(
        'assetIntegrityMismatch',
        'Bundled asset size mismatch.',
      );
    }
    await target.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    operation._progress.add(
      TilawaAssetProgress(
        expected.name,
        bytes.lengthInBytes,
        expected.bytes,
        1,
      ),
    );
  });

  TilawaAssetInstall _install(
    TilawaAssetManifest manifest,
    Future<void> Function(TilawaAssetInstall, TilawaAssetFile, File) write,
  ) {
    final operation = TilawaAssetInstall._();
    // Give the caller a chance to attach result/progress handlers before work.
    scheduleMicrotask(() async {
      Directory? staging;
      String? installing;
      var installRegistered = false;
      try {
        operation._check();
        final root = await _root();
        installing = p.join(root.path, manifest.installationKey);
        if (TilawaPreparedAssets._deleting.contains(installing)) {
          throw const TilawaException(
            'assetsInUse',
            'Asset deletion is in progress.',
          );
        }
        TilawaPreparedAssets._installing.update(
          installing,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        installRegistered = true;
        final existing = await available(manifest);
        operation._check();
        if (existing != null) {
          operation._result.complete(existing);
          return;
        }
        staging = await root.createTemp('.install-');
        TilawaPreparedAssets._activeStages.add(staging.path);
        for (final expected in manifest.files) {
          operation._check();
          final partial = File(
            p.join(staging.path, '${expected.name}.partial'),
          );
          await write(operation, expected, partial);
          operation._check();
          await _verify(partial, expected);
          await partial.rename(p.join(staging.path, expected.name));
        }
        operation._check();
        await File(
          p.join(staging.path, 'installation.json'),
        ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
        final finalDirectory = Directory(
          p.join(root.path, manifest.installationKey),
        );
        try {
          await staging.rename(finalDirectory.path);
          TilawaPreparedAssets._activeStages.remove(staging.path);
          staging = null;
        } on FileSystemException {
          // Another installer may have atomically completed this same version.
          final winner = await available(manifest);
          if (winner == null) rethrow;
        }
        operation._result.complete(_prepared(manifest, finalDirectory));
      } catch (error) {
        operation._result.completeError(
          operation._cancelled
              ? const TilawaException(
                  'assetCancelled',
                  'Installation cancelled.',
                )
              : error is TilawaException
              ? error
              : TilawaException('assetInstallationFailed', '$error'),
        );
      } finally {
        operation._client?.close(force: true);
        if (installRegistered && installing != null) {
          final count = TilawaPreparedAssets._installing[installing] ?? 0;
          if (count <= 1) {
            TilawaPreparedAssets._installing.remove(installing);
          } else {
            TilawaPreparedAssets._installing[installing] = count - 1;
          }
        }
        if (staging != null && await staging.exists()) {
          try {
            await staging.delete(recursive: true);
          } on FileSystemException {
            /* Not usable as installed assets. */
          }
          TilawaPreparedAssets._activeStages.remove(staging.path);
        }
        unawaited(operation._progress.close());
      }
    });
    return operation;
  }
}

TilawaPreparedAssets _prepared(
  TilawaAssetManifest manifest,
  Directory directory,
) => TilawaPreparedAssets._(manifest, {
  for (final file in manifest.files)
    file.name: File(p.join(directory.path, file.name)),
}, directory);
Future<void> _verify(File file, TilawaAssetFile expected) async {
  if (!await file.exists()) {
    throw TilawaException('assetMissing', 'Missing ${expected.name}.');
  }
  if (await file.length() != expected.bytes ||
      (await sha256.bind(file.openRead()).first).toString() !=
          expected.sha256) {
    throw TilawaException(
      'assetIntegrityMismatch',
      'Integrity mismatch for ${expected.name}.',
    );
  }
}

String newTilawaId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
