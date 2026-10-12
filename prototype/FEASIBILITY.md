# Phase 1: Bridge feasibility

Date: 2026-10-12. Status: Android offline replay, ten recreation cycles and 125-second live microphone evidence recorded; Phase 1 partial, iOS runtime unverified. This report supports PLAN.md, not a competing implementation plan.

## Phase 0 confirmation

The existing handoff is complete: independent public Android/iOS 16+ SDK, recognition/tracking first, consumer-owned analytics, optional metadata, separate asset licenses. No product decisions were reopened. The root workspace has an unborn `master` branch; no dedicated SDK repository has been initialized.

## Pinned baseline and integrity

- Upstream commit: `2f2617460dc4a6b967e0cc49fa04804bbf22ec69`, core metadata `0.4.0`. Source files are fetched from immutable raw URLs and verified against the commit's Git blob hashes.
- Model: release asset `606503050`, 69,246,033 bytes, SHA-256 `bfb5b712695634a6099b45a6a78003bd5103417c4eae6338277d54679254905a`.
- Corpus: release asset `569433023`, 5,453,439 bytes, SHA-256 `24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127`.
- Model I/O: release asset `606503126`, SHA-256 `7dca1dafd6ee26044a0d3ba6b9483278203f55df7cc95d40cda865183a0d797e`.
- ORT Web `1.24.2`, esbuild `0.27.3`; npm lockfile records dependency integrity. Flutter probe uses Flutter 3.35.1 / Dart 3.9.0, webview_flutter 4.13.0 and record 6.1.2, with its own pubspec.lock.
- Two upstream benchmark clips, `ref_112001` and `multi_113_001_005`, are pinned through the same tree and Git blob identities. These are smoke fixtures, not an independent accuracy benchmark.

`baseline.json` is machine-readable. `tools/prepare.mjs` retains partial downloads until complete and checks the expected size/hash before installing assets. Generated source/runtime/model files are ignored by Git; setup requires network, recognition does not.

## Ecosystem check

Bounded searches: pub.dev `tilawa`, GitHub repositories `tilawa flutter` and `"tilawa" "sdk"` on 2026-10-12.

- No reusable SDK identified in these searches. pub.dev fuzzy search returned unrelated packages; this is not a reservation/availability guarantee for `tilawa_flutter`.
- [Mo-Sowan/tilawa-hifdh](https://github.com/Mo-Sowan/tilawa-hifdh) is a related Flutter application with a Dart/native FastConformer pipeline. Its README is relevant prior art, but does not demonstrate a current Zipformer SDK/bridge. GitHub metadata reports no license; no code copied. Its web ConvInteger limitation is specific to its alternate model and is not proof that this Zipformer model fails WASM.
- Other returned repositories describe Quran audio playback or personal trackers, not wrappers for this upstream recognition pipeline.

## Candidate comparison

| Requirement | Embedded JavaScript + native ONNX | Local WebView + WASM |
|---|---|---|
| Reuse upstream preprocessing/search/tracking | Bundle unchanged TypeScript | Bundle unchanged TypeScript |
| Mobile JS candidate | flutter_js: QuickJS Android, JavaScriptCore iOS | System Android WebView, WKWebView iOS |
| BigInt/int64 | Must verify actual plugin binaries, tensor conversion and promises | Must verify actual system engine; JS typed tensors remain within one runtime |
| ONNX integration | Custom asynchronous `OrtSessionLike` adapter and tensor ownership | Existing ort namespace/runtime injection |
| Data movement | Many cache tensors cross a native seam unless handles are retained | Only PCM input and JSON observations cross Flutter seam |
| Scheduling | JS runtime API is synchronous FFI; isolate/job-pump integration needs investigation | Single-thread WASM initially; native/browser UI competition needs measurements |
| Local assets | File loading + bundled JS | Same-device loopback server + bundled JS/WASM, no CDN |
| Android requirements | Depends on chosen native runtime and page-size support | Prototype API 24+, system WebView capabilities still required |
| iOS requirements | Native ONNX candidate requires iOS 16/static linkage | Prototype targets iOS 16; WKWebView WASM and local transport require device proof |
| Resource risk | Cache ownership/leaks, marshaling cost, plugin binary support | Browser/WASM memory, startup copying, single-thread sustained processing |
| Status | Reviewed candidate, not implemented or rejected | First minimal prototype selected, not final SDK architecture |

Sources: pinned `recitation/zipformerRunner.ts` and `session.ts`, [flutter_js](https://pub.dev/packages/flutter_js), [flutter_onnxruntime](https://pub.dev/packages/flutter_onnxruntime), [webview_flutter](https://pub.dev/packages/webview_flutter). Plugin documentation is support information, not end-to-end evidence.

The native candidate remains a deliberate alternative if WebView measurements are unsuitable. A full Dart port is not authorized by this prototype selection.

## Prototype scope

- Private `app/` Flutter application, not the public SDK scaffold/API.
- Compile the pinned upstream ZipformerSession directly with esbuild. Disable structural correction; retain upstream recognition semantics.
- Package JS, single-thread ORT WASM, pinned model/corpus/I/O, notices and two benchmark clips locally for this probe. Model bundling here is a feasibility convenience, not the release distribution policy.
- Serve assets from an app-owned directory on a random loopback port/path. No host-PC server, hosted Tilawa site, external script CDN or audio upload. Navigation and CSP restrict the browser to the local origin.
- Session feed/control calls are serialized. Returned upstream event arrays are not re-emitted: observations flow through `onEvent` exactly once.
- PCM16 input is converted to normalized float32. Replay decodes/resamples locally to mono 16 kHz. Optional native microphone capture requests mono 16 kHz, bounds pending chunks and reports overruns; delivered hardware rate and interruption correctness still need validation.
- Inference calls and timings are instrumented around the actual ORT `run()`, with generation/event sequence/processed-input position. Positions are not word timestamps; stop tail samples are not counted as externally fed audio.
- Stop/reset, silence, paced replay, explicit ORT release/recreation are exercised by the probe controls. Background microphone capture is stopped; no background recognition claim.

## Artifact inventory

| Artifact | Terms/source |
|---|---|
| Bundled upstream TS implementation | Upstream MIT, preserved TILAWA_LICENSE and TILAWA_NOTICE.md |
| Model, phoneme corpus, vocabulary/derived artifacts | NPL-1.2 per pinned NOTICE; NPL-1.2.txt travels with the runtime |
| I/O manifest | Release-associated artifact, kept with model/license |
| ONNX Runtime JS/WASM | MIT plus third-party notices from version v1.24.2 |
| Flutter WebView plugin | BSD-3-Clause, notices via Flutter dependency packaging |
| record/path_provider and transitive plugins | Dependency licenses via Flutter packaging; no claim that these make every asset MIT |
| Benchmark audio | Copied only for local verification from pinned upstream tree; upstream corpus provenance must be reviewed before redistribution of clips |
| Authored bridge/probe code | Wrapper license undecided; private, publish_to none |

## Evidence and remaining gates

- Setup actually completed: 39 pinned source/manifest files verified, model/corpus/I/O/NPL verified, local JS/WASM bundle generated (approximately 86.1 MiB total with model and clips), Flutter dependencies resolved.
- Connected physical device: Infinix X678B, Android 14 / API 34, arm64. No emulator is used.
- Android debug APK built and installed. Actual inference produced the expected 112:1 final sequence and 113:1-5 final sequence, verse matches and word progress. Silence returned an empty sequence; reset, stop and explicit ORT release/reinitialization completed.
- Preliminary single-thread timings: 2.917 s clip processed in 10.148 s; 24.292 s clip processed in 56.012 s, with 54 actual inference calls; paced version 54.770 s. Device was found locked/dozing afterward, so stable-foreground measurements are required before drawing performance conclusions.
- Preliminary memory snapshot: app process PSS 412,135 KiB; associated WebView renderer PSS 301,796 KiB at a separate sampling time. Not a synchronized total, peak or leak measurement; debug runtime and asset mappings contribute.
- First build hit Windows Kotlin incremental-cache cross-drive C:/E: error; prototype disables Kotlin incremental compilation. Analyzer then clean and debug APK build succeeded. No authored test suite added/run.
- Owner unlocked phone for foreground repeat. Probe keeps its own Android window awake. Android arm64 release APK built (73.8 MB), installed and run in the foreground. Release lint initially required explicit includeSubdomains attributes in the local network policy; fixed without disabling lint.

### Foreground release results

Environment: physical Infinix X678B, Android 14/API 34, system WebView 153.0.8010.36; Flutter 3.35.1, ORT Web 1.24.2 WASM. Foreground focus confirmed via Android window state.

| Probe | Actual outcome |
|---|---|
| Runtime initialization | 7,354 ms; real ONNX graph reports 99 inputs/100 outputs; BigInt64Array and WASM available |
| Threaded-WASM request | Requested 4; effective 1. crossOriginIsolated=false, SharedArrayBuffer unavailable despite COOP/COEP headers |
| Single ayah, 2.917 s input | Expected 112:1; matched final sequence, 1 verse match, 2 word-progress events, 9 inference calls; 3,070 ms including stop flush |
| Multi ayah, 24.292 s input | Expected 113:1-5; exact final sequence, 5 verse matches, 49 word-progress events, 54 inference calls; 12,805 ms total, 12,346 ms inference |
| Silence, 2 s input | Empty final sequence, no verse matches; 8 inference calls, 1,809 ms inference |
| Real-time-paced multi replay | Same exact sequence/progress; 25,164 ms total including deliberate pacing and stop tail; 11,824 ms actual inference |
| Dispose/reinitialize | ORT release completed; recreation 3,916 ms, then 112:1 matched again with word progress in 1,993 ms |
| Automatic probe completion | AUTORUN_COMPLETE observed, no runtime errors in the captured probe summary |

Replay now checks the expected final sequence plus nonzero word progress before returning a successful sample result. Only these two smoke clips were checked. Timing includes upstream stop's synthetic silence tail; short-clip elapsed/input ratios are not steady-state throughput measurements. Paced elapsed time includes intentional waiting. The locked/debug and foreground/release runs differ in multiple conditions; their timing difference is not attributed to a single cause.

After the release run, app PSS was 332,081 KiB (about 324 MiB), including 199,276 KiB graphics. Its associated renderer PSS was 308,972 KiB (about 302 MiB) at a separate sampling time. Renderer association was checked through Android activity-process package/service records. These are not synchronized peak measurements or proof of leak-free disposal. The observed footprint is a material tradeoff to review before selecting this architecture for the SDK/Qiyam.

### Original handoff gates and decision

The following list records the original handoff. The continuation section below supersedes its outstanding Android offline/live-format/resource checks and paused status.

- Owner personally tested the installed prototype and reported that it looked excellent and worked quickly. Exact test conditions were not supplied; this feedback is retained separately from the measured replay/lifecycle results above. Work is paused at the owner's request for continuation in a new session.
- WebView/WASM is a credible **Android candidate** based on actual graph inference, recognition/progress, paced replay and reset/stop/recreation. It is **not yet the finalized SDK architecture**.
- Native-JS/native-ONNX remains available for comparison if sustained performance or memory targets make WebView unsuitable. Do not infer that native is faster until measured.
- Network-disabled fresh/warm initialization and replay remain unverified. All runtime resources are local and CSP restricts fetches, but no device connectivity setting was changed in this session.
- Native microphone live feed, hardware rate/channel confirmation, sustained capture/overrun, permission denial, interruptions and audio route changes remain unverified.
- Baseline/peak/stress memory, repeated release/recreate memory behaviour and Android 16 KB native-library compatibility remain unverified.
- Quantitative startup/latency/memory targets still require owner agreement using the measurements above.
- iOS build/device/runtime results: unavailable on this Windows host; needs Mac/Xcode and physical iPhone. Phase 1 cannot be marked complete without that evidence.
- Microphone permission denial, native rate/channel delivery, audio route changes and real recitation outcomes remain distinct from replay checks.
- Broad parity/accuracy, extended sustained capture, Android 16 KB release compatibility and final dependency/platform minimums are not established by two clips.

Next bounded work: native microphone/input and network-disabled checks, resource measurements against agreed targets, then run the same pinned probe on a physical iPhone using Mac/Xcode. Keep Phase 1 partial until both-platform acceptance evidence exists. Actual publication, later API implementation and Qiyam integration remain separate work.

## Continuation checkpoint (2026-10-12)

- Owner confirmed prior personal success was live microphone recitation. Mac/iPhone unavailable; agreed to measure first before setting quantitative resource limits.
- Dedicated local SDK Git repository initialized with authorization. Existing source/handoff saved as `f981d91`; generated/downloaded assets and builds remain ignored. No remote or push.
- Added private Android client/device recording-format and app-PSS snapshots, microphone byte/feed/queue/observation-count diagnostics, optional five-minute stop timer and ten bounded release/reinitialize cycles. No microphone references/transcripts logged. Pause/stop recorder state now ends capture; starting capture checks current foreground lifecycle.
- Analyzer clean; updated arm64 release APK built and installed on the reconnected Infinix. Airplane mode=1 and Wi-Fi disabled confirmed by ADB before fresh-process initialization, all replay probes and ten extra recreation cycles. AUTORUN_COMPLETE observed.
- Offline fresh initialization 7,660 ms. Single clip 2,799 ms; multi clip 12,641 ms (12,168 ms inference); paced multi 25,179 ms (11,773 ms inference). Expected sequences/progress passed; silence empty. Warm recreation 3,513 ms; captured extra-cycle initialization readings approximately 3.10..3.47 s. This is offline reuse of already-installed assets, not offline installation.
- Twelve sequential app/associated-renderer memory samples across late recreation cycles and settling: app PSS 349,887..354,938 KiB; renderer PSS 313,680..497,814 KiB, settling near 313,681 KiB. App graphics approximately 199,012 KiB. Samples are adjacent, not synchronized or true peaks. Renderer rise during recreation remains a material tradeoff; this bounded run is not a leak-free proof.
- Release APK passes build-tools 36 zipalign `-c -P 16 -v 4`. Both packaged arm64 native libraries, libapp.so and libflutter.so, have ELF LOAD alignment 0x10000 (64 KiB). Static alignment evidence only; physical 16 KB-page Android runtime unverified.
- Android record_android 1.5.2 PCMReader uses AudioRecord and emits little-endian signed PCM16; observed active recording reports both client and device formats as 16,000 Hz, one channel, encoding=2 (PCM16), builtin microphone type=15, not silenced. Android dumpsys audio independently confirmed client/device formats. This is the system-reported capture configuration, not a measurement of the microphone ADC's physical clock.
- Source-only iOS review: record_ios 1.2.1 RecorderStreamDelegate explicitly uses AVAudioConverter from native input format to requested interleaved PCM16 rate/channels. This is not iPhone/runtime proof.

### Offline live microphone pass

Owner started live recitation manually, then tapped Stop mic after 125 seconds. After clarifying that five minutes is only the optional measurement-build timer, not a proposed SDK limit, the owner chose to save this evidence and defer the full five-minute pass.

| Measurement | Recorded result |
|---|---|
| Capture elapsed | 125,314 ms |
| Accepted PCM input | 4,006,400 bytes, 125.2 s at observed mono 16 kHz PCM16 |
| Successfully fed PCM | Same 4,006,400 bytes; 2,003,200 samples confirmed by bridge |
| Pending queue | High-water one 480 ms chunk; zero pending/remainder at completion |
| Overruns | Zero |
| Feed request latency | 261 calls, mean 220.433 ms, max 277.601 ms |
| Stop inference flush | 845 ms after capture stop/drain |
| Actual inference | 262 calls, 53,056.8 ms including stop tail |
| Recognition observations | Six verse matches and 210 word-progress messages |

Observation counts are not unique ayah counts or repeat counts. Recited references/audio were not saved in diagnostics, so this pass demonstrates actual live recognition/progress and throughput, not independently verified passage accuracy. Byte accounting covers chunks accepted by Dart before stop, not proof that hardware delivered every acoustic sample up to the stop boundary. Feed request latency is not acoustic word-to-highlight latency. Lifecycle/route behaviour was not exercised in this pass.

Four sequential ADB memory pairs during late capture and after stop: app PSS 342,965 / 351,758 / 339,139 / 337,731 KiB; associated renderer PSS 355,710 / 322,275 / 321,721 / 320,854 KiB. Captured periodic native app snapshots during the pass included 363,552 KiB. Swap PSS was nonzero (approximately 18..21 MiB app and 4..7 MiB renderer in those pairs), so PSS alone understates retained footprint. These are samples, not synchronized totals or true peaks.

### Remaining gates after continuation

- Full five-minute sustained microphone pass deferred by owner; only the measured 125.2 s input is established. Automatic five-minute timer is source-prepared, not runtime-verified.
- Permission denial/recovery, background/lock/audio-focus interruption, route changes, restart after these conditions and true renderer teardown remain unverified.
- Agree startup/responsiveness/memory budgets with owner using measured results. Adjacent recreation PSS sampling showed a large transient renderer footprint; no architecture approval or leak-free claim.
- Static arm64 ZIP/ELF alignment checked; 16 KB-page runtime and other architectures unverified.
- Mac/Xcode and physical iPhone unavailable. Both-platform Phase 1 evidence remains partial. Owner subsequently accepted the Android checkpoint and approved Phase 2 API design; deferred checks remain release gates and architecture stays provisional. See ../API_CONTRACT.md for the review draft.
