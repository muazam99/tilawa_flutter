# tilawa_flutter (development SDK)

Independent Flutter integration for Tilawa's offline Zipformer Quran recognition. This is a development SDK, not a published package. Android device checks cover recognition, tracking, offline setup and recovery. Physical route/renderer/native cleanup and platform/resource gates remain open. Authored code is MIT licensed; third-party and asset terms are listed in [NOTICE.md](NOTICE.md). Final runtime selection remains under review.

Current Android native checks include five-minute paced input, five-minute foreground capture and five reset/disposal cycles. Broader fixtures retain the known mixed-passage omissions. Earlier WebView recreation produced a material renderer-memory spike. These are device-specific development checkpoints, not full-Quran accuracy, leak-free cleanup or final release acceptance.

Android checks do not establish iOS support or close deferred fault/resource gates. See [API_CONTRACT.md](API_CONTRACT.md) and [example evidence](example/README.md) for contract details and verification limits.

## Requirements

- Flutter 3.35.1 / Dart 3.9 or newer compatible versions.
- Intended platforms: Android API 24+ and iOS 16+. Physical iPhone verification is pending.
- Android app: INTERNET permission for asset downloads. Native recognition reads verified local files and needs no loopback server. The checked-in example also permits loopback for the optional WebView runtime.
- iOS app: iOS 16 deployment target and local-network ATS configuration, as prepared in `example/ios/Runner/Info.plist`. iOS build/runtime is not verified on this Windows host.
- Optional microphone: Android RECORD_AUDIO permission and iOS NSMicrophoneUsageDescription. The helper requests permission only when start is called.

## Standalone developer example

The conventional [example app](example/README.md) uses only the exported SDK APIs. It downloads missing pinned assets into an app-owned persistent store, supports per-file progress/cancel/retry and local-only reopen, and exposes explicit live Start/Stop, Reset and Dispose controls. No Node/cache/private probe inputs are required. Android/iOS platform configurations are checked in; verification status is recorded in its README.

Its nine-ayah112/113 corpus-label fixture is distributed under NPL-1.2 with the full license in SDK runtime assets. Recognition elsewhere retains references/indices with an honest unavailable-display state. Event counts are example-owned observations, not repeat credit or page completion. See [NOTICE.md](NOTICE.md) for the5A distribution/license inventory and open release decisions.

Runtime JS/WASM and third-party notices are package assets under `assets/runtime`. Consumers do not need Node/npm. The large model, phoneme corpus and benchmark audio are not SDK package assets.

Until publication, add this SDK as a local path dependency named `tilawa_flutter`
in your app's pubspec.yaml, pointing at the package directory, and run
`flutter pub get`. Add microphone permission only if using the optional helper.
Downloaded recognition assets total about 74.7 MB; bundled runtime assets total
about 14 MB. These are asset sizes, not the installed application's memory cost.
The Android native default replaces the prior WebView recognition backend, whose
recreation checks sampled over 1 GiB of renderer memory. Native development checks
show substantially lower added recognition RAM with the same model and matching
rules. Compiled numeric tracker/alignment kernels preserve float32 rounding and
tie-breaking while removing the long-ayah throughput regression. On the measured
Android phone, added steady recognition PSS was about 142 MiB versus 359 MiB for
WebView, and 51.9 seconds of long-ayah audio processed in 40.2 seconds. Device samples are
not worst-case memory bounds. Prefer one active session and reset it between runs
when healthy.

## Local files and external audio

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:tilawa_flutter/tilawa_flutter.dart';

final assets = await TilawaAssets.fromLocalFiles(
  manifest: TilawaAssetManifest.zipformerV1(),
  model: File(modelPath),
  corpus: File(corpusPath),
  io: File(ioManifestPath),
  license: File(nplLicensePath),
);
final session = await TilawaSession.open(assets: assets);
final subscription = session.events.listen((event) {
  if (event is TilawaWordProgress) {
    // 0-based ayah-local indices. Replace the current snapshot.
    // matchedIndices includes unsure words, not certified correct coverage.
    onProgress(event);
  }
});
try {
  // Your bounded producer supplies mono 16 kHz Float32List PCM in [-1, 1].
  await for (final Float32List chunk in mono16kAudio) {
    await session.feed(chunk);
  }
  final result = await session.stop();
  // Choose this Future OR TilawaSessionEnded for result aggregation.
  onResult(result);
} finally {
  await session.dispose();
  await subscription.cancel();
}
```

`onProgress`, `onResult`, paths and `mono16kAudio` are application-provided. A default chunk is limited to one second; outstanding in-flight/pending PCM is limited to two seconds. Feed copies input at admission. Await feeds in order; async stream callbacks are not a bounded capture queue. Rejected audioOverrun input is not silently dropped or accepted.

Stop is terminal/idempotent. Reset starts another run using the same healthy runtime; dispose releases it without implicit finalization. Interrupt attempts bounded finalization and explicitly distinguishes incomplete output from an empty recognized sequence. Quarantined/failed runtimes require a new session. There is no five-minute SDK limit.

The Android development default uses native ONNX Runtime 1.24.2 for inference and
the pinned Tilawa matching core in a QuickJS worker isolate, with two compiled
Dart numeric kernels for tracker costs and word alignment. Recurrent tensors stay
native; each session owns its model, state and worker. Dispose waits for actual
native cleanup before releasing asset leases. The package supplies ONNX JNI R8
keep rules and checks the native runtime version. iOS retains the provisional
WebView/WASM backend and still needs physical-device validation.

## Downloaded or bundled assets

```dart
// Use a dedicated, application-owned persistent directory.
final store = TilawaAssetStore(Directory(assetStoragePath));
final manifest = TilawaAssetManifest.zipformerV1();
var assets = await store.available(manifest);
if (assets == null) {
  final installation = store.download(manifest, retries: 2);
  final progress = installation.progress.listen(onAssetProgress);
  try {
    assets = await installation.completed;
  } finally {
    await progress.cancel();
  }
  // installation.cancel() aborts active network work and incomplete staging.
}
final session = await TilawaSession.open(assets: assets);
```

Progress reports per-file bytes and attempt. Size/SHA-256 verification precedes atomic installation. Content-addressed versions do not overwrite older valid versions; retry starts a fresh incomplete download, not HTTP-range resume. `fromBundled(manifest, assetKeyMap)` installs app-bundled assets through the same verification path. Flutter AssetBundle loads each file into memory, so large bundled models have a temporary memory cost; prefer local/downloaded files when appropriate.

`available` verifies an installed version; corrupt versions produce assetIntegrityMismatch rather than being trusted. `delete(manifest)` refuses installations leased by open sessions or active installers. `cleanupInterruptedInstallations()` removes reserved `.install-*` staging folders left by process termination, without touching completed versions or active installs in the same Dart isolate. Use one coordinating isolate for a store. Cross-process/isolate installation locking is not implemented. Direct external file mutations/deletions cannot be prevented by the SDK.

## Optional microphone

```dart
import 'package:tilawa_flutter/microphone.dart';

final microphone = await TilawaMicrophone.open(session: session);
final captureErrors = microphone.errors.listen(onCaptureError);
await microphone.start();
// Later, after the user chooses to finish:
await microphone.stopCapture();
final result = await session.stop();
await microphone.dispose();
await captureErrors.cancel();
```

Capture uses pinned record plugin PCM16 delivery, converted to normalized float32, with 480 ms chunks and a bounded producer queue. Android source requests this client format through AudioRecord; iOS source converts hardware input through AVAudioConverter. The helper does not claim it measured the physical hardware rate. Its hardwareFormatVerified getter is false. Unsupported/failed native capture produces explicit errors, not arbitrary raw-PCM rate assumptions.

Foreground-only. Audio-focus pause/disconnection or app backgrounding stops capture and requests a session interruption; resume is explicit. Continuity-breaking interruptions and disposal discard capture not yet submitted to the session. Interruption starts the session deadline before awaiting capture drain. Normal stop drains queued capture including the partial final chunk, bounded by interruptionDeadline; expiry reports operationTimeout and requests processingStalled interruption. This does not preempt native OS calls or guarantee native recorder teardown. No automatic microphone start, background recognition or recording upload. Android denial/background/audio-focus recovery passed; physical route/disconnection remains unverified. Session disposal also disposes its attached helper. Dispose and await helper cleanup before replacing it; only one helper can attach to a ready/accepting session, and the attachment remains reserved until recorder cleanup succeeds.

## Metadata and analytics

An optional TilawaMetadataResolver binds a display edition to the exact corpus hash and `tilawaSegmentationId`. The session captures its edition/version identity at open; switching either requires a new session/resolver. resolveMetadata validates that identity, ayah word counts and explicit recognition-to-display mappings; recognition works without it. A mapping may be ayah-only or cover every recognition word with display IDs/page/juz references. Word rows must carry at least one reference; supplied display IDs must be nonblank and unique within a row. One-to-many and many-to-one mappings across rows are allowed. Page/juz references must be positive. An ayah-only mapping has no word rows.

Metadata mismatches and resolver failures produce nonfatal warnings and rejected lookup Futures, not invalid highlights or recognition failure. Validation checks declared identity and structure; the developer still verifies their actual text/edition segmentation and the accuracy of layout references. The SDK cannot certify arbitrary display labels from a claimed hash alone.

Consumers replace word-progress and transcript snapshots rather than unioning/appending them. Capture the event run ID, selected ayah and a request generation before asynchronous metadata lookup, then check them again before updating the display. Reset clears presentation state, and a lookup started in an older run must not overwrite the new one. The standalone consumer in `example/lib/demo_controller.dart` demonstrates these guards, mapped Arabic words, references and optional live input. Its small 112/113 fixture is developer-supplied, not a default SDK Quran edition. There is no SDK highlight widget, page completion or analytics UI.

Scores are preserved engine values, not probabilities; accumulated scores may exceed 1. Repeated progress does not mean new words read, verse suppression prevents a complete repeated-reading history, and fallback verse matches do not imply actual word coverage. See API_CONTRACT section 6 for pinned source details.

At the pinned baseline, stop fallback runs only when no verse has emitted. A short passage recognized by fallback alone can be omitted when later live matches occur in the same run. Android mixed-passage checks also omitted early ayahs after a tracked passage change. Finalization complete means the runtime drained/flushed successfully, not that the final sequence contains everything recited. No missing references or reading occurrences are synthesized.

Lost/relocated observations are opt-in diagnostics at this pinned baseline, not a guaranteed typed transition stream. A lost diagnostic can coexist with sampled tracking state `tracking`; retain that distinction instead of inventing a complete loss/recovery history. Android repetition checks produced additional progress with no new verse matches, then located a different surah in the same run.

## Attribution and development

Tilawa upstream: <https://github.com/yazinsai/tilawa>, pinned commit `2f2617460dc4a6b967e0cc49fa04804bbf22ec69`. ONNX Runtime Web 1.24.2. This is an independent integration, not an official upstream package. See [NOTICE.md](NOTICE.md) and bundled license files.

Maintainer runtime generation: after the prototype's locked dependencies and verified source/assets are prepared, run `node tool/prepare_sdk_runtime.mjs`. It rechecks source Git blob identity and emits bridge/WASM/notices with an integrity manifest. Generated SDK runtime assets are tracked; model/corpus/audio and build products are excluded. The old Phase 1 probe remains separate. The private Phase 3 SDK validation entry point is `prototype/app/lib/sdk_probe.dart`.
