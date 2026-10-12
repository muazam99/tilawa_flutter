# Phase 1: Bridge feasibility

Date: 2026-10-12. Status: Android release replay/lifecycle smoke evidence recorded; Phase 1 partial, iOS runtime unverified. This report supports PLAN.md, not a competing implementation plan.

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

### Remaining acceptance gates and decision

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
