// Private, opt-in Phase 3A device checks. Fixtures never enter recognition.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tilawa_flutter/tilawa_flutter.dart';

typedef AssetProbeLog = void Function(String);

void requireAssetProbe(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> expectAssetError(
  String code,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } on TilawaException catch (error) {
    requireAssetProbe(error.code == code, 'Expected $code, got $error');
    return;
  }
  throw StateError('Expected $code, operation succeeded');
}

Future<void> _settled(TilawaAssetInstall install) => install.progress.drain();

Future<({TilawaAssetStore store, TilawaPreparedAssets assets})> runAssetProbe(
  Directory support,
  AssetProbeLog log,
) async {
  final manifest = TilawaAssetManifest.zipformerV1();
  final root = Directory('${support.path}/tilawa-sdk-asset-probe');
  await root.create(recursive: true);
  final store = TilawaAssetStore(Directory('${root.path}/fresh'));
  final marker = File('${root.path}/crash-seeded');
  final seedDone = await marker.exists();
  final stale = await store.cleanupInterruptedInstallations();
  requireAssetProbe(
    !seedDone || stale == 1,
    'Expected one killed-install stage',
  );
  log('ASSET_RECOVERY stale=$stale processKill=$seedDone');

  // First launch deliberately stalls after real HTTPS bytes arrive. The
  // operator force-stops the app at CRASH_READY, then relaunches this build.
  if (!seedDone) {
    await store.delete(manifest);
    final network = _ProbeNetwork(gateFirstResponse: true);
    final install = network.run(() => store.download(manifest));
    var announced = false;
    final progress = install.progress.listen((event) async {
      if (!announced && event.receivedBytes > 0) {
        announced = true;
        await marker.writeAsString('partial HTTPS download', flush: true);
        log(
          'ASSET_CRASH_READY file=${event.file} bytes=${event.receivedBytes}',
        );
      }
    });
    try {
      await install.completed;
      throw StateError('Crash-seed download unexpectedly completed');
    } finally {
      await progress.cancel();
    }
  }

  // Keep the earlier successful bundled installation as a preservation witness.
  final baseline = TilawaAssetStore(
    Directory('${support.path}/tilawa-sdk-assets'),
  );
  requireAssetProbe(
    await baseline.available(manifest) != null,
    'Baseline bundled installation is missing',
  );

  await store.delete(manifest);
  final cancelNetwork = _ProbeNetwork(gateFirstResponse: true);
  final cancelled = cancelNetwork.run(() => store.download(manifest));
  final cancelledClosed = _settled(cancelled);
  var cancelBytes = 0;
  final cancelProgress = cancelled.progress.listen((event) {
    cancelBytes = event.receivedBytes;
    cancelled.cancel();
  });
  await expectAssetError('assetCancelled', () async {
    await cancelled.completed;
  });
  await cancelledClosed;
  await cancelProgress.cancel();
  requireAssetProbe(cancelBytes > 0, 'Cancellation did not reach network data');
  requireAssetProbe(
    await store.available(manifest) == null,
    'Cancelled installation was activated',
  );
  requireAssetProbe(
    await store.cleanupInterruptedInstallations() == 0,
    'Cancellation left a stale stage',
  );
  log('ASSET_CANCEL bytes=$cancelBytes noActivation=true noStage=true');

  final license = manifest.file('NPL-1.2.txt');
  TilawaAssetManifest fixture(String id, {bool wrongHash = false}) =>
      TilawaAssetManifest(
        id: 'private-storage-probe-$id',
        engineId: manifest.engineId,
        engineVersion: manifest.engineVersion,
        upstreamCommit: manifest.upstreamCommit,
        segmentationId: manifest.segmentationId,
        ioSchema: manifest.ioSchema,
        files: [
          for (final file in manifest.files)
            TilawaAssetFile(
              name: file.name,
              bytes: license.bytes,
              sha256: wrongHash ? '0' * 64 : license.sha256,
              license: 'Storage-only license-text fixture, not engine assets',
              downloadUri: license.downloadUri,
            ),
        ],
      );
  final fixtures = TilawaAssetStore(Directory('${root.path}/fixtures'));
  final retryManifest = fixture('retry');
  await fixtures.delete(retryManifest);
  final retryNetwork = _ProbeNetwork(failRequests: 1);
  final retry = retryNetwork.run(() => fixtures.download(retryManifest));
  final retryClosed = _settled(retry);
  final retryEvents = <TilawaAssetProgress>[];
  final retryProgress = retry.progress.listen(retryEvents.add);
  await retry.completed;
  await retryClosed;
  await retryProgress.cancel();
  requireAssetProbe(
    retryNetwork.requests == 5,
    'Unexpected retry request count',
  );
  requireAssetProbe(
    retryEvents.isNotEmpty && retryEvents.first.attempt == 2,
    'Retried file did not report attempt 2',
  );
  log('ASSET_RETRY requests=${retryNetwork.requests} firstAttempt=2');

  final exhaustedManifest = fixture('exhausted');
  await fixtures.delete(exhaustedManifest);
  final exhaustedNetwork = _ProbeNetwork(failRequests: 99);
  final exhausted = exhaustedNetwork.run(
    () => fixtures.download(exhaustedManifest, retries: 1),
  );
  final exhaustedClosed = _settled(exhausted);
  await expectAssetError('assetInstallationFailed', () async {
    await exhausted.completed;
  });
  await exhaustedClosed;
  requireAssetProbe(
    exhaustedNetwork.requests == 2,
    'Retry budget was exceeded',
  );
  requireAssetProbe(
    await fixtures.available(exhaustedManifest) == null,
    'Failed download was activated',
  );
  log('ASSET_RETRY_EXHAUSTED requests=2 noActivation=true');

  final badManifest = fixture('bad-hash', wrongHash: true);
  await fixtures.delete(badManifest);
  final integrityNetwork = _ProbeNetwork();
  final bad = integrityNetwork.run(() => fixtures.download(badManifest));
  final badClosed = _settled(bad);
  await expectAssetError('assetIntegrityMismatch', () async {
    await bad.completed;
  });
  await badClosed;
  requireAssetProbe(
    integrityNetwork.requests == 1,
    'Integrity failure should not be retried',
  );
  requireAssetProbe(
    await fixtures.available(badManifest) == null,
    'Integrity mismatch was activated',
  );
  log('ASSET_HASH_REJECT requests=1 noActivation=true');

  // Exercise same-isolate installation coordination through a gated bundle.
  final bytes = await rootBundle.load('assets/runtime/NPL-1.2.txt');
  final bundle = _ProbeBundle(bytes);
  final concurrentManifest = fixture('concurrent');
  await fixtures.delete(concurrentManifest);
  final keys = {for (final file in manifest.files) file.name: file.name};
  final first = fixtures.fromBundled(concurrentManifest, keys, bundle: bundle);
  final firstClosed = _settled(first);
  await bundle.entered.future;
  await expectAssetError(
    'assetsInUse',
    () => fixtures.delete(concurrentManifest),
  );
  requireAssetProbe(
    await fixtures.cleanupInterruptedInstallations() == 0,
    'Cleanup removed an active install',
  );
  final second = fixtures.fromBundled(concurrentManifest, keys, bundle: bundle);
  final secondClosed = _settled(second);
  bundle.release.complete();
  final installed = await Future.wait([first.completed, second.completed]);
  await Future.wait([firstClosed, secondClosed]);
  requireAssetProbe(
    installed[0].installationDirectory!.path ==
        installed[1].installationDirectory!.path,
    'Concurrent installs diverged',
  );
  requireAssetProbe(
    await fixtures.cleanupInterruptedInstallations() == 0,
    'Concurrent installs left staging',
  );
  log(
    'ASSET_CONCURRENT sameVersion=true activeStageProtected=true deleteBlocked=true',
  );

  // Corruption on disk must be detected on subsequent availability checks.
  await installed.first.files['corpus.json']!.writeAsBytes(Uint8List(1));
  await expectAssetError('assetIntegrityMismatch', () async {
    await fixtures.available(concurrentManifest);
  });
  await fixtures.delete(concurrentManifest);
  requireAssetProbe(
    await fixtures.available(retryManifest) != null,
    'Deleting one version damaged a different valid version',
  );
  log('ASSET_CORRUPTION_REJECT otherVersionPreserved=true');

  final fresh = store.download(manifest);
  final freshClosed = _settled(fresh);
  final last = <String, TilawaAssetProgress>{};
  var invalidProgress = false;
  final freshProgress = fresh.progress.listen((event) {
    final previous = last[event.file];
    final valid =
        event.receivedBytes > 0 &&
        event.receivedBytes <= event.expectedBytes &&
        (previous == null ||
            event.attempt > previous.attempt ||
            event.receivedBytes >= previous.receivedBytes);
    if (!valid) invalidProgress = true;
    last[event.file] = event;
    if (event.receivedBytes == event.expectedBytes) {
      log(
        'ASSET_DOWNLOAD_FILE ${event.file} bytes=${event.receivedBytes} attempt=${event.attempt}',
      );
    }
  });
  final assets = await fresh.completed;
  await freshClosed;
  await freshProgress.cancel();
  requireAssetProbe(!invalidProgress, 'Invalid progress');
  requireAssetProbe(
    last.length == manifest.files.length &&
        last.values.every(
          (event) => event.receivedBytes == event.expectedBytes,
        ),
    'Missing final per-file progress',
  );
  requireAssetProbe(
    await store.available(manifest) != null,
    'Downloaded installation was not reusable',
  );
  requireAssetProbe(
    await baseline.available(manifest) != null,
    'Earlier bundled installation was damaged',
  );
  log('ASSET_FRESH_COMPLETE files=${last.length} baselinePreserved=true');
  // Make another explicit run start a new crash/recovery cycle.
  await marker.delete();
  return (store: store, assets: assets);
}

Future<void> runResponseRecoveryProbe(
  Directory support,
  AssetProbeLog log,
) async {
  final base = TilawaAssetManifest.zipformerV1();
  final license = base.file('NPL-1.2.txt');
  TilawaAssetManifest fixture(String id) => TilawaAssetManifest(
    id: 'private-response-$id',
    engineId: base.engineId,
    engineVersion: base.engineVersion,
    upstreamCommit: base.upstreamCommit,
    segmentationId: base.segmentationId,
    ioSchema: base.ioSchema,
    files: [
      for (final file in base.files)
        TilawaAssetFile(
          name: file.name,
          bytes: license.bytes,
          sha256: license.sha256,
          license: 'Storage-only NPL license text, never recognition input',
          downloadUri: license.downloadUri,
        ),
    ],
  );
  final store = TilawaAssetStore(
    Directory('${support.path}/tilawa-response-recovery'),
  );
  for (final mode in ['retry', 'exhausted', 'cancel']) {
    final manifest = fixture(mode);
    await store.delete(manifest);
    final network = _ProbeNetwork(failBodies: mode == 'exhausted' ? 99 : 1);
    final install = network.run(() => store.download(manifest, retries: 1));
    final closed = install.progress.drain<void>();
    final progress = <TilawaAssetProgress>[];
    final sub = install.progress.listen((event) {
      progress.add(event);
      if (mode == 'cancel' && event.attempt == 1) install.cancel();
    });
    if (mode == 'retry') {
      await install.completed;
      requireAssetProbe(
        network.requests == 5 && progress.any((e) => e.attempt == 2),
        'Body retry did not restart correctly',
      );
      requireAssetProbe(
        await store.available(manifest) != null,
        'Body retry failed verification',
      );
    } else {
      await expectAssetError(
        mode == 'cancel' ? 'assetCancelled' : 'assetInstallationFailed',
        () async {
          await install.completed;
        },
      );
      requireAssetProbe(
        await store.available(manifest) == null,
        'Failed body activated partial files',
      );
      requireAssetProbe(
        network.requests == (mode == 'cancel' ? 1 : 2),
        'Body retry exceeded budget',
      );
    }
    await closed;
    await sub.cancel();
    requireAssetProbe(
      progress.any(
        (e) =>
            e.attempt == 1 &&
            e.receivedBytes > 0 &&
            e.receivedBytes < e.expectedBytes,
      ),
      'Fault did not follow partial bytes',
    );
    requireAssetProbe(
      await store.cleanupInterruptedInstallations() == 0,
      'Body recovery left stale staging',
    );
    if (mode != 'retry') {
      requireAssetProbe(
        await store.available(fixture('retry')) != null,
        'Body fault damaged prior version',
      );
    }
    log(
      'RECOVERY_DOWNLOAD mode=$mode requests=${network.requests} partialBytes=true stagingClean=true previousVersionPreserved=true',
    );
  }
}

// Narrow private transport hook. Real HTTPS/redirects/TLS remain Dart-owned.
final class _ProbeNetwork extends HttpOverrides {
  _ProbeNetwork({
    this.failRequests = 0,
    this.gateFirstResponse = false,
    this.failBodies = 0,
  });
  final int failRequests;
  final bool gateFirstResponse;
  final int failBodies;
  int requests = 0;
  T run<T>(T Function() action) =>
      HttpOverrides.runWithHttpOverrides(action, this);
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ProbeClient(super.createHttpClient(context), this);
}

final class _ProbeClient implements HttpClient {
  _ProbeClient(this.inner, this.network);
  final HttpClient inner;
  final _ProbeNetwork network;
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    network.requests++;
    if (network.requests <= network.failRequests) {
      throw const SocketException('Private probe transient request failure');
    }
    final request = await inner.getUrl(uri);
    return (network.gateFirstResponse && network.requests == 1) ||
            network.requests <= network.failBodies
        ? _ProbeRequest(
            request,
            failBody: network.requests <= network.failBodies,
          )
        : request;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ProbeRequest implements HttpClientRequest {
  _ProbeRequest(this.inner, {this.failBody = false});
  final HttpClientRequest inner;
  final bool failBody;
  @override
  HttpHeaders get headers => inner.headers;
  @override
  Future<HttpClientResponse> close() async =>
      _ProbeResponse(await inner.close(), failBody: failBody);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ProbeResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _ProbeResponse(this.inner, {this.failBody = false});
  final HttpClientResponse inner;
  final bool failBody;
  @override
  int get statusCode => inner.statusCode;
  @override
  int get contentLength => inner.contentLength;
  Stream<List<int>> _body() async* {
    await for (final chunk in inner) {
      if (failBody) {
        yield chunk.sublist(0, chunk.length > 1 ? chunk.length ~/ 2 : 1);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        throw const SocketException('Private mid-response disconnection');
      }
      yield chunk;
      // A cancellable stalled response, also used for the process-kill seed.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ProbeBundle extends CachingAssetBundle {
  _ProbeBundle(this.bytes);
  final ByteData bytes;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ByteData> load(String key) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return bytes;
  }
}
