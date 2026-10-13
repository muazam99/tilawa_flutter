# Tilawa Flutter: Phase 1 probe

A private Android/iOS probe for the pinned upstream Zipformer pipeline. Phase 0 is complete. Phase 1 has Android recognition evidence but remains incomplete until the outstanding gates in [FEASIBILITY.md](FEASIBILITY.md) are addressed.

## Setup

Requirements: Node.js 22+, Flutter 3.35.1 / Dart 3.9 or compatible, Android SDK for Android, Mac/Xcode/CocoaPods and an iPhone for iOS. The prototype targets Android API 24+ and iOS 16+. Windows cannot validate the iOS build.

From `tilawa_flutter/prototype`, install the locked tooling with `npm ci --ignore-scripts`, then run `npm run prepare:runtime`. Setup downloads and verifies the pinned source, model, corpus, I/O manifest, notices and two sample clips, then generates a local JS/WASM bundle.

From `tilawa_flutter/prototype/app`, run `flutter pub get`, then `flutter devices` and `flutter run --release -d <device-id>`. Use a physical device and keep the app foregrounded.

For automatic replay/lifecycle probes: `flutter run --release -d <device-id> --dart-define=PROBE_AUTORUN=true`.

For the bounded threaded-WASM experiment: append `--dart-define=PROBE_THREADS=4`. The runtime uses one thread if the WebView lacks actual cross-origin isolation or SharedArrayBuffer. The inspected Android WebView did lack these capabilities, even with COOP/COEP headers.

For the continuation measurement build, append `--dart-define=PROBE_CYCLES=10 --dart-define=PROBE_MIC_SECONDS=300`. Run probes repeats release/initialize/single-ayah recognition for ten extra cycles (allowed range 0..10). Start mic remains manual; the optional deadline stops it after five minutes. Android snapshots distinguish client PCM format from device-side capture format and include app PSS only, not renderer memory. Mic diagnostics record byte counts, feed timings, queue high-water, overruns and observation counts without recited references/transcripts. Sample renderer memory separately through ADB.

## Controls

- **Single ayah:** replay pinned upstream `ref_112001`, expect 112:1.
- **Multi ayah:** replay pinned upstream `multi_113_001_005`, expect 113:1-5.
- **Run probes:** single/multi replay, silence, real-time-paced replay, explicit runtime release/recreation and repeated single-ayah replay. Replay checks require expected final sequences and nonzero word progress; no accuracy generalization is implied.
- **Start mic / Stop mic:** optional native PCM16 capture and Flutter-to-JS feed path. Grant microphone permission, recite, then stop. Requested capture format is mono 16 kHz; delivered hardware format, sustained latency, real recitation and interruptions require separate validation. Microphone transcripts/payloads are not printed to the device log.

Observations are raw upstream events with private probe metadata. Word indices are 0-based. Empty display text is intentional: this phase has no display Quran metadata. Phoneme transcripts are not ordinary Arabic text. Duplicate word-progress observations are preserved.

The Android probe holds its own window awake while foregrounded. It does not change system sleep settings. Leaving the foreground stops microphone capture; full interruption/route-change behaviour is not yet established.

## Local runtime and licensing

The app uses an app-owned loopback HTTP server, bundled JS/WASM, and local model/corpus files. No PC server, hosted Tilawa page, CDN script or audio upload is used at recognition time. Android fresh/warm initialization, sample replay and a 125-second live microphone pass succeeded with airplane mode on and Wi-Fi disabled. iPhone offline verification remains outstanding.

Model bundling is for this feasibility probe only. Generated runtime files and downloaded source/models are Git-ignored; they are not the intended public-package archive.

- Upstream code: MIT with the asset exceptions described in the pinned NOTICE.
- Default model/corpus/vocabulary-derived material: NPL-1.2. Keep its license with distribution; powered features cannot be charged for.
- ORT: MIT plus retained third-party notices.
- Benchmark clips: local verification only until provenance/redistribution terms are reviewed.
- Authored wrapper license remains undecided; this app has `publish_to: none`.

Android release builds currently use Flutter's generated debug signing key for local installation. The 73.8 MB arm64 APK is a probe artifact, not a store/public SDK release.

## Evidence

### Phase 3 public-facade probe

The app now has a path dependency on the root development SDK. To build the private SDK integration entry point use `flutter build apk --release --target-platform android-arm64 -t lib/sdk_probe.dart`. It installs/reuses the four verified bundled assets, locally decodes/resamples the pinned multi-ayah fixture, feeds the public API and reports canonical stop/result identity, reset, silence, disposal and local asset reuse. No microphone starts. It needs no mounted inference WebView widget on the verified Android run. The separate fixture decoder uses a temporary local WebView.

Latest installed APK is this entry point, not the older interactive Phase 1 mic screen. Restore that screen with the default lib/main.dart entry point if microphone checks are requested. See ../../PHASE3.md for the public facade's actual results and remaining gates. Large assets/audio in this private app remain excluded from root SDK package assets.

Opt-in Phase 3 diagnostics use the same `lib/sdk_probe.dart` target:

- `--dart-define=PROBE_ASSETS=true`: real HTTPS downloads and private fault hooks. Requires the baseline bundled install from a default run. First launch logs ASSET_CRASH_READY after real bytes arrive; force-stop then relaunch to check interrupted staging cleanup. It subsequently checks cancel/retry/integrity/concurrency/version protection and downloaded-assets recognition. This uses dedicated disposable probe stores, preserving the baseline store. Retry fixtures contain license text, never recognition input.
- `--dart-define=PROBE_CONTROLS=true`: bounded facade diagnostics through the public adapter factory, including overload, copied admission, terminal identity, timeout quarantine/late output, competing stop/reset, and disposal with a stalled feed. These are synthetic adapter checks, not native preemption or WebView-crash evidence.
- `--dart-define=PROBE_MIC=true`: after replay, opens an interactive screen using `TilawaMicrophone`. Capture starts only on Start or Lifecycle check. Stop ends capture then finalizes recognition; Reset enables a new run. Lifecycle check performs five seconds of capture/normal stop/helper disposal, then a three-second capture/session disposal. Recreate opens a fresh session/helper. Logs include counts/state/sample positions, not transcripts or recited references.

Controls and microphone flags can be combined. Do not combine microphone with asset checks: the asset run deliberately deletes its downloaded installation after lease validation. Offline validation requires disabling external connectivity explicitly; OFFLINE_REUSE alone is a filesystem check. Device results and remaining gates are in PHASE3.md.

### Phase 4 tracking and developer metadata

Target `lib/tracking_probe.dart` to open the private tracking consumer. Add `--dart-define=PROBE_TRACK_CONTRACT=true` for isolated event/metadata checks through a scripted public adapter, and `--dart-define=PROBE_TRACK_AUTORUN=true` for two Al-Falaq replays separated by silence, followed by a 112:1 recording in the same run. The current installed Android build uses both flags. Start mic remains explicit; no automatic capture occurs.

The consumer displays discovered candidates, tracked ayah, Arabic word labels, latest tracker snapshot and page/juz references. It replaces revisions, preserves repeated observations, labels scores/indices limitations and rejects stale asynchronous mappings after reset/ayah changes. Lost is an opt-in diagnostic, not a fabricated complete tracking-transition stream. Observation counts are debugging metrics, not repeat credit or reading analytics.

The checked-in private fixture contains nine ayahs/38 recognition words from surahs112/113, with page604/juz30 references. Arabic labels are exactly pinned corpus w[2], excluding display end markers; NPL-1.2 applies. To regenerate, run `node tools/prepare_tracking.mjs <developer-pages.json> <developer-juz.json>` from prototype. The script verifies corpus SHA-256, full-ayah single-page counts and juz ranges, retains source hashes, and rejects ambiguous mappings. Its JSON is a private consumer format, not a public SDK serialization contract. It is not a default full-Quran metadata dataset or the Phase5 public example.

Recorded Android Phase4 outcomes: 17 mapping mismatch modes/resolver-failure rejection without recognition failure; repeated/revised snapshots, lost diagnostic/sample-state distinction, immutable payloads, finite scores above1, terminal ordering and reset-generation guards. Real fixture validation succeeded for all nine ayahs. Repeating113 produced zero new verse matches and46 new progress observations; switching to112:1 yielded final113:1-5,112:1 (six matches/97 progress). Owner confirmed live words/ayah followed recitation; successful live stop recorded five sequence entries/485120 external samples. Earlier exploratory live stops returned zero/two entries; this is functionality evidence, not an accuracy benchmark. Actual acoustic lost/relocated diagnostics were not observed in the prerecorded run (located3/completed2); scripted source-compatible diagnostics validate the facade contract separately.

See [FEASIBILITY.md](FEASIBILITY.md), including continuation evidence and remaining gates. Device logs have the prefix `TILAWA_PROBE`. Five-minute automatic stop is a configurable measurement-build convenience, not an SDK duration limit. Android offline/live/recreation results do not establish iPhone, longer sustained capture, interruptions or leak-free cleanup.

### Phase 5C recovery diagnostics

Build lib/sdk_probe.dart in release/arm64 with `--dart-define=PROBE_RECOVERY=true --dart-define=PROBE_RECOVERY_REQUIRE_FIXED=true --dart-define=PROBE_CONTROLS=true`. This opt-in build explicitly starts short real microphone captures for fault/lifecycle checks, unlike the ordinary replay build; grant permission first and keep it foregrounded. It uses400ms interruption/2s disposal budgets and a controlled stalled adapter, then private HTTPS partial-response faults, a competing native audio-focus request, existing controls and normal real-WebView replay. No audio/transcripts are logged or saved by capture diagnostics. Intentionally failed cleanup retains a lease until process exit; force-stop this private app after checks. Log prefix TILAWA_SDK; expected RECOVERY_CHECKS_COMPLETE, RECOVERY_DOWNLOAD, RECOVERY_NATIVE_FOCUS, CONTROL_CHECKS_COMPLETE and SDK_COMPLETE. See ../../PHASE3.md for actual outcomes and limitations.

For the real JavaScript bridge fault, build with only `--dart-define=PROBE_NATIVE_BRIDGE=true`, launch, and immediately run `node tools/recovery_bridge.mjs <adb-executable>` from prototype/. The probe enables WebView debugging temporarily, opens the local runtime and waits20seconds after RECOVERY_NATIVE_BRIDGE_READY. The tooling creates/removes a temporary ADB forward, installs a CDP hook that errors a pending feed through the real JavaScript channel, and posts late output. Expect RECOVERY_NATIVE_BRIDGE with rejected pending feed, fenced late output and fresh-session completion. Debugging is disabled in cleanup; force-stop if tooling fails or the diagnostic is interrupted. This is a controlled real-JavaScript bridge failure, not a renderer-process crash. That5C private build was76.9MB; latest5D build is described below. The standalone19.0MB example remains installed with assets retained and session/helper disposed.

### Phase 5D private Android validation

From prototype/, `node tools/prepare_validation.mjs` downloads eight benchmark clips from the pinned upstream commit and verifies their Git blobs, with size/SHA-256/source/expected-reference receipts in ignored app/assets/runtime/validation_samples.json. Benchmark redistribution terms remain unresolved; these clips and generated receipts stay private, outside the public example/package runtime. The core/model/corpus pins are unchanged.

Build lib/performance_probe.dart in release/arm64 with `--dart-define=PROBE_VALIDATION=broader` for beginning/middle/end references, a long ayah, second-source/ambiguous input and derived mid-ayah/noisy/silence/repeat+switch cases. It records expected alternatives versus actual canonical sequences, candidates, progress, fallback diagnostics and elapsed time; mismatches are evidence, not silently converted to success. Eight clips plus four derived cases are a small functionality set, not full-Quran accuracy or certified correctness. Decoder/resampler is private consumer code, not an SDK feed feature.

Use `--dart-define=PROBE_VALIDATION=switch-only` for the additional repeat of live-tracked2:255 followed by1second silence and113fixture. Both mixed-passage checks produced incomplete expected sequences on Android; retain the recorded limitations. Fallback-only1:2 preceding113was omitted; tracked2:255 was retained once but113:1–2 were omitted. Do not infer full reading history or fabricate missing verses from neighboring matches. See FEASIBILITY for exact outcomes/source semantics.

Build the same entry point with `--dart-define=PROBE_VALIDATION=resources` for five minutes of paced repeated fixture input, five minutes of real foreground capture, then five runtime recreation/reset/disposal cycles and settling. This opt-in build starts capture automatically after paced input; grant permission and keep the phone unlocked/foregrounded. Stop validation ends the bounded workload early. It records asset verification, initialization, feed mean/p95/max, schedule lag, sampled submitted-minus-processed high-water, capture errors, terminal sample counts and native app-PSS. Sampled session outstanding audio is not the helper's private producer-queue high-water. Ambient capture validates throughput/lifecycle, not independent live-recognition accuracy. Private instrumentation wraps the actual WebView implementation; ordinary consumers/example still use only public barrels. No production metrics API is added.

After launch, run `node tools/capture_validation.mjs <adb-executable> <label>` from prototype/ to collect TILAWA_PERF logs and30-second sequential app/associated-renderer PSS/RSS/swap samples under ignored .cache/validation-evidence. Renderer association uses the probe's scoped Android service records, not every WebView on the phone. The collector stops on COMPLETE/ERROR or15minutes. Native app samples and ADB app/renderer samples have different timing; these are not synchronized totals, true peaks or leak-free proof. Locked/background runs are rejected by the probe and excluded from foreground acceptance evidence.

2026-10-13 checkpoint: analyzer clean/89.5MB private arm64 builds passed; all eight individual clips plus mid-ayah/noise/silence behaved as expected, two mixed-passage cases retained as incomplete recognition outcomes. Five-minute paced4.8million samples and300.115s mic capture/4,798,720samples completed without capture errors; adapter mean feeds226.757/221.834ms respectively. Five recreation/reset/disposal cycles passed. Renderer recreation sample853,740KiB PSS, later reduced; resource budgets/runtime acceptance remain open. Latest installed private entry point is switch-only, force-stopped after checks. Public example/runtime pins are unchanged by5D; no publication candidate claim. Full measurements in FEASIBILITY.md.
