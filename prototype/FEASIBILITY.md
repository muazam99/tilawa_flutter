# Phase 1: Bridge feasibility

Latest RAM checkpoint (2026-10-13): native ONNX/QuickJS measured about 53–55% lower added steady recognition RAM and passed exact Falaq progress parity, five-minute paced/microphone checks and five recreations. Broader references remain consistent, but long-ayah feeding is slower than incoming audio (60.052s for 51.918s, max feed3.555s); CPU tuning did not resolve it. Runtime acceptance and the optimization goal remain incomplete. A private native-inference/browser-matching hybrid has built/analyzed, with no device evidence yet. Resume from PLAN.md's latest RAM checkpoint; earlier archive/runtime status entries below are historical.

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

## Phase 5D Android broader-passage checkpoint (2026-10-13)

Owner authorized Android broader/sustained/resource validation; iPhone deferred for now. Private release/arm64 performance_probe.dart on Infinix X678B/Android14, Flutter3.35.1/Dart3.9, unchanged pinned model/core/runtime. New benchmark downloads verified against immutable Git blobs at2f2617460dc4a6b967e0cc49fa04804bbf22ec69, with size/SHA-256/provenance/expected alternatives in ignored prototype/app/assets/runtime/validation_samples.json. Audio/receipts remain private; redistribution terms unresolved. Public display fixture remains112/113 only.

The preliminary run started while the phone was dozing; its timings are excluded. Restarted unlocked/foreground after adding interactive/keyguard/lifecycle guards. Analyzer clean;89.5MB private arm64 APK includes additional benchmark inputs, not SDK archive or public-example size. Private decoder/resampler prepares explicit mono16kfloat32 before public feed. Completed foreground results:

| Case | Input seconds | Observed canonical result | Progress / limitation |
|---|---:|---|---|
| Beginning, ref_001002 |5.534|1:2|0progress; stop fallback only, score1 not word-coverage proof |
| Long ayah, ref_002255 |51.918|2:255|99progress |
| Middle, multi_036_001_005 |28.600|36:1–5|31progress |
| Middle, multi_059_022_024 |61.308|59:22–24|110progress; sequence score0.98 |
| End, multi_114_001_006 |41.469|114:1–6|56progress |
| Second-source retasy_004 |4.400|114:3|0progress; stop fallback only |
| Shared/ambiguous phrase, user_imran_23 |11.563|3:23|8progress, score0.65; pinned manifest also accepts4:44 |
| Existing multi_113_001_005 |24.292|113:1–5|49progress |
| Mid-ayah start, final60% of2:255 clip |31.151|2:255|63progress; score0.54, no full-ayah coverage implication |
| Attenuated/noisy113 fixture |24.292|113:1–5|48progress;0.35gain plus seeded uniform noise amplitude0.025, not general noise-robustness evidence |
| Three-second silence |3.000|Empty|No match/progress |
| Repeat1:2,1s silence, switch113 |36.359|113:1–5 only|Expected1:2 then113:1–5 not met;38progress, locateFailed diagnostic. Earlier fallback-only passage was not retained in the final sequence |
| Repeat tracked2:255,1s silence, switch113 |129.128|2:255,113:3–5|Expected2:255 then113:1–5 not met;232progress,2located/1idle diagnostics; one2:255 entry despite repetition, first two113ayahs omitted |

All runs finalized completely and processed their submitted PCM. These are eight clips and five derived functionality cases, not an accuracy percentage. Expectations come from the pinned upstream manifest, not independent expert annotation. Correct references can arrive only at final fallback with no live highlighting. Final sequence is not exhaustive reading history, and recognition observations do not certify correctness or complete coverage. Both compound cases are retained as incomplete recognition outcomes, not converted into successful full-passage claims. The tracked2:255 case ran separately in a fresh process,63.581s processing including stop for129.128s input.

Pinned source explains the fallback-only caveat: session.ts574..604 invokes fallback at stop, gated by emission.ts136..138 requiring zero emitted verses. Once113matches have emitted, stop cannot recover an earlier fallback-only1:2. Missing113:1–2 in the separately tracked switch case is an observed recognition/acquisition limitation; no wrapper result or history is fabricated to fill it. Consumers that know a passage boundary can explicitly reset, but reset is not an accuracy guarantee.

Foreground fixture processing elapsed3.658s/5.534s input (including stop),25.908s/51.918s long ayah,30.468s/61.308s59passage and12.483s/24.292s113fixture. These unpaced complete-operation timings are not sustained throughput or acoustic word-to-highlight latency. Sustained/resource measurement completed separately below; final runtime/budget acceptance remains pending.

Raw evidence is in ignored prototype/.cache/validation-evidence/broader-foreground-events.log and broader-foreground-memory.jsonl. Private benchmark decoding creates temporary WebViews and additional allocations, so its memory samples are workload/probe measurements, not isolated SDK footprint. See prototype/README for reproduction and later resource checkpoint.

## Bounded 5D acceptance follow-up (2026-10-13)

Owner approved a focused follow-up, paused for clarification, then resumed. The completed broader/sustained suite was not repeated. Pinned core/model/runtime remain unchanged; only private probe/collector diagnostics changed. Physical Infinix X678B/Android14, foreground release/arm64, local verified assets.

### Recognition attribution

The saved1:2 compound result and pinned session.ts574..604/emission.ts136..138 establish the fallback policy limitation: once another verse emits, stop fallback cannot recover an earlier fallback-only passage. The saved tracked-switch log contained aggregate observations, so one targeted replay added adapter-boundary tracing, without modifying recognition or the bridge.

That replay reproduced2:255,113:3–5. Raw events showed2:255 acquisition, later idle/lost, then candidate/located113:3; no113:1–2 word progress or matches. Raw final_sequence, adapter stop snapshot and public canonical result agreed. All2,066,046samples processed,232progress events, complete finalization. Progress briefly referenced2:256 with no match, illustrating that cursor/progress is not recognized reading history. This establishes an engine acquisition/emission omission for this case, not references dropped by the Dart canonical-result wrapper; it does not isolate the underlying acoustic/search cause or approve recognition quality.

### Decoder-free recreation

Separate fresh process using default public TilawaSession.open, no custom adapter, fixture decoding, loaded audio or microphone. Three sequential open/feed32,000silence samples/stop/dispose cycles,5second holds around checkpoints, then fixed90second settling. APK89.4MB still packages ignored benchmark assets but does not load/decode them in this mode. UI/native diagnostic overhead remains; this is not exact incremental SDK memory.

- Asset reuse verification2.296s. Opens7.460/5.720/5.972s including asset verification. All three results complete,32,000submitted/processed each, empty sequences. Disposal returned in50/82/85ms; this is API completion, not renderer-process destruction.
- Scoped service association: app PID7314, one renderer PID15497 throughout observed runtime samples. Five-second periodic plus checkpoint samples include individual timestamps; app/renderer samples remain sequential and are not a true peak.
- Third recreation renderer PSS rose through743,554/838,760/1,086,086 to **1,092,906KiB (about1,067MiB or1.04GiB)**, RSS1,180,320KiB. Adjacent app PSS285,412KiB. Swap-PSS was small here (app137/renderer310KiB), unlike the earlier sustained microphone evidence.
- Renderer fell to415,814KiB about1.3seconds after the highest sample, then413,626 after disposal. First low sample91,861KiB was about11.4seconds after final disposal; final90second-settle checkpoint91,383KiB PSS/311KiBswap. Renderer remained alive. App settled around281..283thousandKiB, versus pre-runtime baseline230,766KiB; retained app memory is not attributed entirely to SDK or proven leaked.

**Assessment:** High recreation memory also occurs without fixture decoding or sustained capture. The earlier834MiB sample cannot be dismissed as decoder-only overhead. Later reclamation is observed, but allocation cause, worst-case bounds and low-memory behavior remain unresolved. No agreed budgets or final runtime acceptance. Recommend a separate bounded allocation/teardown investigation before finalizing5E; do not silently select native runtime, infer a leak, or repeatedly rerun the completed sustained suite. Recognition limitations still require owner acceptance or separately scoped engine work. iPhone remains deferred and other native/hardware gates remain open.

Private ignored evidence: acceptance-tracked-switch-events.log/-memory.jsonl and acceptance-isolated-recreation-events.log/-memory.jsonl under prototype/.cache/validation-evidence. Probe Dart format/analyzer and collector Node syntax checks passed; both arm64 builds completed (recreation build logged a Kotlin daemon startup retry but succeeded). Latest recreation-only APK force-stopped after completion. No authored unit-test suite, root SDK/runtime changes, commit/push/publication or5E progression.

## Phase 5D Android sustained/resource checkpoint (2026-10-13)

### Later stopped RAM-investigation checkpoint (2026-10-13)

After the bounded follow-up, owner authorized further work, then explicitly stopped before the newest candidate's device measurement completed. Preserve these distinct statuses:

- A dedicated-worker experiment still sampled1,091,291KiB rendererPSS during recreation and was removed. Private explicit native WebView.destroy also sampled1,073,897KiB. Each completed three silence operations, but left the foreground during settling; neither establishes a fix or complete acceptance. Evidence labels worker-isolated-recreation/native-destroy-recreation remain ignored/private.
- Completed heap-gc-recreation-bounded diagnostic used temporarily enabled WebView debugging and CDP forced collection after disposal. Reported backingStorage fell from about63.6millionbytes to0 and JSusedSize from about11.9million to0.41millionbytes. Following renderer samples fell from about335..340thousandKiB to83..90thousandKiB; subsequent opens sampled around400thousandKiB. This supports delayed realm reclamation, but instrumentation/forcedGC alters behavior and is not a production solution or true-peak bound. Initial collector fetch hang produced no memory evidence; a3second abort was added, and subsequent startup/CDP timeouts were recorded without suppressing native samples. Temporary CDP forwards were removed/debugging disabled after completion.
- Current experimental SDK candidate briefly recycles at most one released Android browser realm for15seconds, with fresh recognition sessions, cleared model/file mappings, removed disposed callbacks, and adapter epoch fencing in source/generated bridge. Idle expiry closes local transport/runtime files. iOS remains uncached. This affects runtime ownership and needs lease/concurrency/error/deadline and real-device regression review before acceptance. No forcedGC is used in SDK code.
- Candidate root analyzer initially reported one brace-style info, corrected without a subsequent analyzer run. Candidate arm64 release build succeeded (89.5MB). Install/collector command was interrupted by owner stop, so no candidate memory improvement, lifecycle result or successful install is established. Private probe was force-stopped afterward. Current progress is saved by owner request, not claimed release-ready. No new unit-test suite,5E–G completion, push/publication or iPhone evidence.

Fresh private-app process, unlocked foreground throughout, USB charging, physical Infinix X678B/Android14, WebView153.0.8010.36, unchanged local WebView/WASM runtime. Standalone asset availability/integrity verification2.844s. First session.open6.951s includes another asset verification; adapter/runtime initialization portion4.931s. These are verified local reuse/fresh-process measurements, not fresh-download/first-install startup or cold-storage-cache guarantees.

| Measurement | Paced recitation input | Foreground microphone |
|---|---:|---:|
| Workload | Repeated pinned113fixture, bounded480ms sequential producer | Real native capture; ambient/user audio not stored or referenced in logs |
| Duration |300.000s input;301.132s elapsed including final flush|300.115s capture wall time;299.920s PCM submitted |
| Processed / submitted samples |4,800,000 /4,800,000|4,798,720 /4,798,720 |
| Feed requests |625|625 |
| Feed request mean / p95 / max |226.757 /247 /352ms|221.834 /240 /304ms |
| Final inference flush |826ms|2304ms after capture stop/drain |
| Finalization |Complete|Complete |
| Continuity/backlog evidence |Maximum completion lag354ms; it did not grow across the five-minute schedule|0capture errors/overruns;100ms-sampled session outstanding high-water7680samples (one480ms chunk) |

The external producer awaits feeds and does not queue unbounded input. Microphone's sampled submitted-minus-processed position is not its private producer-queue high-water and can miss brief transients; absence of capture errors plus equal final sample accounting is the observed continuity evidence. PCM timing covers data accepted by Dart, not every physical acoustic sample up to the stop boundary. Immediate MIC_BEGIN format snapshot was empty; use the separate5C delivered-format evidence, not an inferred fresh hardware measurement. Feed times are whole adapter requests, not CPU utilization or acoustic word-to-highlight latency. This ambient/live capture is sustained processing/lifecycle evidence, not independently verified recitation accuracy. Five minutes is a diagnostic duration, not an SDK limit.

Five subsequent runtime recreation/reset/disposal cycles completed. Session.open5.806..6.522s, adapter initialization3.566..4.480s; each session processed silence, stopped, reset, processed again and disposed. Native app-PSS after final15-second settling sample244,256KiB. No unbounded queue growth or capture failure observed on this device; this is not a universal performance or leak-free claim.

### Resource tradeoff and acceptance

Scoped ADB service records associated renderer PID24735 with private app16762. Sequential30-second samples, separate from native app samples:

- Paced workload app PSS271,931..306,104KiB (about266..299MiB); renderer339,400..387,181KiB (about331..378MiB).
- Mic workload app PSS269,141..283,292KiB (about263..277MiB); renderer378,362..391,647KiB (about369..382MiB). Observed swap-PSS reached41,888KiB app/82,994KiB renderer (about41/81MiB), so resident PSS alone understates retained footprint.
- Recreation sample at09:12:58 local time: renderer PSS853,740KiB (about834MiB), RSS932,820KiB. A later recreation sample fell to445,393KiB PSS. This is the highest sampled value, not a true peak or synchronized app+renderer total.
- Later idle check around09:26..09:27, roughly13minutes after completion: app242,459KiB PSS/34,841KiB swap; renderer113,357KiB PSS/45,007KiB swap. The renderer remained alive after SDK disposal; its delayed drop is not proof of immediate destruction or guaranteed reclamation.
- Battery temperature samples34.0°C during the sustained run, USB charging. No battery-consumption assessment or thermal-throttling guarantee follows.

These measurements include the private Flutter UI/fixture decoder and app/renderer resources, not isolated incremental SDK overhead. Sustained processing keeps up here, but the material recreation footprint remains an explicit runtime/resource acceptance decision. No memory budget has been agreed and the bridge architecture remains provisional. A change of runtime needs separate bounded implementation/revalidation; this checkpoint does not silently choose an alternative.

Raw ignored evidence: resources-foreground-events.log/resources-foreground-memory.jsonl and tracked-switch-events.log/tracked-switch-memory.jsonl under prototype/.cache/validation-evidence. Analyzer clean and89.5MB arm64 release builds for broader/resources/switch-only passed. Latest private installed build is switch-only, force-stopped after checks. Public example still19.0MB with retained downloaded assets and microphone/session disposed. No production SDK runtime/model/corpus changes in5D or authored unit-test suite. Owner subsequently requested a local5C/Android5D progress commit; no push/dryrun/publication or Qiyam integration. iPhone deferred for now; physical routes/renderer/native teardown and16KB-device runtime gates remain open. Final intended-platform/resource/recognition acceptance is not complete.

## Android development/package handoff (2026-10-13 continuation)

Owner authorized completion/device control, chose MIT for authored wrapper/example code, kept public URLs unset until a repository exists, and chose to keep WebView provisional while finishing packaging. No commit/push/publication requested.

- Baseline7036940/master; current source/docs are uncommitted. Original realm-cache candidate stalled its second open. Changed native JS channel ownership to a stable router with a detachable consumer callback, so a cached page keeps its channel without retaining the disposed adapter. Adoption assigns a fresh callback/epoch; failed detach closes transport/files. Cleanup attempts transport/file removal even when earlier cleanup fails.
- Normal-release three decoder-free cycles completed with32,000 processed/submitted samples each; opens7.292/4.881/4.778s, disposals40/46/59ms. Associated renderer sampled406,840KiB PSS (397MiB), final90s sample72,579KiB (71MiB); app max273,175KiB/final247,660KiB, sampled separately. No debugger/forcedGC. Better quick sequential reuse, not a universal bound or leak-free proof.
- Final reuse-recognition probe: fresh, quick-reused and post16s-expiry sessions each returned113:1–5, five matches/50progress,388,670processed samples and complete finalization. Two simultaneous sessions kept16,000/8,000samples independent; disposal/expiry completed. Renderer sampled1,284,829KiB PSS (1.23GiB) near concurrent disposal, later607,933KiB. Concurrent/expired allocations still have material memory cost. Prefer one active session/reset healthy runs; runtime/resource acceptance remains provisional.
- Package-only isolated example built19.0MB/analyzed clean from91 audited source/resource files, without prototype/tool/model/cache dependencies. Temporary applicationID dev.tilawa.tilawa_flutter_package_check gives independent empty storage. Fresh74.7MB HTTPS installation/runtime ready; Dispose then airplane1/Wi-Fi0/data0/no default/current networks -> local reopen ready. Microphone client/device16kmonoPCM16, normalStop complete with1,845,760processed/submitted samples. Ambient fallback55:31/no progress is lifecycle evidence, not accuracy. Original connectivity0/1/1 restored. Temporary app/probe force-stopped and temporary mic permission revoked; original public example/data preserved. Preexisting tcp53373 forwarding untouched; diagnostic53374 removed. Device page size4096, not16KB.
- Authored code LICENSE=MIT (Muaz Amir,2026), asset/runtime/example-metadata exceptions retained inNOTICE. AddedCHANGELOG/.pubignore, public ownership/index/score/result comments, narrow patch dependency ranges and honest memory/platform docs. Version0.1.0-dev.1/publish_to:none retained. URLs intentionally unset. Root/probe/isolated example analyzers and arm64 release builds passed. Java build loopback failure resolved with command-local jdk.net.unixdomain.tmpdir pointing at short ignored workspace directory; no global Java setting changed.
- Dart pub publish --dry-run completed with no validation errors and two warnings: owner-unset repository/homepage and uncommitted tracked changes. Runtime/notices/public example present; private prototypes/tools/audio/models/build/credentials excluded. Audited archive/files/hash are retained under ignored prototype/.cache/package-review; exact final archive values are recorded in PLAN's handoff. This is a development archive, not publication clearance.
- Remaining release gates: Mac/Xcode/physical iPhone; available physical headset/input-route disconnection; renderer-process death/native cleanup faults beyond controlled evidence;16KB-device runtime; low-memory-device/resource budgets; acceptance of upstream mixed-passage omissions; actual repository/publisher/final release version and clean owner-reviewed source. 5E/5F development work and this5G provisional handoff do not mark full Phase5 complete. Publication and Qiyam integration remain separate requests.

Private evidence: recycled-recreation-verified and recycled-channel-fixed are incomplete stalled attempts; recycled-inspection completed with debugging enabled/no forcedGC; recycled-release-final is the normal-release memory reference; reuse-recognition-final is the recognition/expiry/concurrency reference. All rawlogs/audio remain ignored.

R2 completed: same decoder-free PCM/harness on unlocked Infinix X678B. Baseline steady SDK increment366727KiB; basic373003KiB; no-prepack366060.5KiB; URL346708KiB (~5.5% lower). All two-run113:1–5/50progress/sample accounting passed, elapsed12.2..12.9s/24.29s input. URL loading sampledmax459521KiB vs baseline508251KiB (~9.6% lower), insufficient for30% active-RAM goal. These are development experiments, not new public defaults. R3 native adapter added privately using same pinned Tilawa core/model, QuickJS matching and native retained recurrent states; prototype dependencies flutter_js0.8.7/flutter_onnxruntime1.8.1. Android Gradle forces ONNXRuntime1.24.2 (plugin default1.23.0 is overridden); public SDK dependencies/runtime selection unchanged. Native build/device evidence pending. New source needs parity, deadline/callback/tensor ownership, worker/UI and sustained/resource verification before adoption.

R3 native QuickJS-NG + documented R8 keep rules completed (ram-r3-native-ng-keep-a): baseline239261KiB, pooled steady native increment147006KiB, active sampledmax173584KiB, loading220925KiB. Both388670-sample113:1–5 runs had5matches/50progress/complete finalization; elapsed19.516/21.043s for24.291875s input, opens7.877/8.147s. Added baseline overhead vsWebView app-only=26017KiB; charging it conservatively gives173023KiB vs366727KiB (~52.8% lower) for steady recognition cost. Target is promising in private prototype, not yet achieved in publicSDK or sustained verification. Native no renderer; app/renderer totals treated separately. Native plugin's backgroundTaskQueue verified in source; JNI keeps fixed native release crash. Batched tensor allocation/disposal candidate builds next with explicit PROFILE_OPEN adapterId; use variant native-batch-v2. Unchanged publicdefault stillWebView. Need exactprogress parity/broader/5minute paced+mic, failure/deadline/lifecycle tests, publicintegration/consumer/package and repeatedpaired evidence beforegoalcompletion.

R3 current native-batch-v2-a completed: app-only232269KiB, steady increment151761KiB (~148.2MiB), active sampledmax180599KiB/loading228263KiB. Charging nativebaseline overhead19025KiB vsoriginalbaseline gives170786KiB vs366727KiB (~53.4% lower). Two113:1–5 runs/50progress each complete,18.110/18.981s vs24.29s input; native inference80..86ms mean, batchedcleanup27..32ms mean. Still private prototype, no publicSDK reduction claim yet. NativeWorkerProbeFactory/worker/core split now analyzer-clean, bootstrap lease/serialized commands and native-cleanup acknowledgment added; worker build in progress. Next verify worker/RAM/parity, promote verified Android backend into publicSDK with runtime pins/integrity/consumerR8rules, thenR4sustained/lifecycle/consumer checks. Preserve iOS WebView behavior/release gates; no Qiyam edits/commit/push/publication.

## Hybrid speed and RAM device checkpoint (2026-10-14)

Resumed clean 1e7bed9/master on physical unlocked Infinix X678B. Hybrid remains private; no public runtime promotion. Long 2:255: 51.918s audio processed in 11.133/10.964s, feed maxima 240/236ms, complete 830688 samples, expected reference and identical 99-snapshot hashes. Decoder-free Falaq two-cycle profile: 5.141/8.682s for 24.292s input, complete 388670 samples/cycle, five references and exact saved 50-snapshot hash de3579d199035f98eae744baeff227d28b881f42d34579b9c84d77fc9ccfccf7.

| Paired app/renderer measurement | Same-day WebView | Hybrid |
|---|---:|---:|
| App-only baseline KiB | 235561 | 233728 |
| Steady recognition increment KiB | 367959 | 276195 |
| Active sampled maximum increment KiB | 495138 | 312958 |
| Loading sampled maximum increment KiB | 580092 | 294264 |

Hybrid saves 24.9% steady recognition PSS, below the 30% target. Against original R1 baseline, charging additional app overhead gives only 19.1% saving. Hybrid final settled increment 66054KiB PSS plus total swap 108239KiB; do not infer complete reclamation from falling PSS. Swap was small during active steady stages (maximum 546KiB). Same-day WebView profile used saved sdk-baseline-profile.apk with native plugin registration, and old verbose progress logging truncated PASSAGE lines; its summary correctly marks recognition accounting unverified. The hybrid compact logs independently establish parity/accounting. Samples are sequential app/renderer observations, not true peaks. Temperatures hybrid 31..32C, baseline 32..34C; no controlled thermal equivalence claimed.

Raw ignored evidence labels: hybrid-long-20261014-a/b, hybrid-ram-20261014-a, webview-ram-20261014-a. APKs preserved under ignored ram-apks. Hybrid release RAM build passed. No sustained/microphone/broader/consumer/archive rerun warranted until a candidate meets both RAM and speed goals; iPhone/hardware/16KB gates remain open. Probe force-stopped after measurements; no microphone started or connectivity changed. Next reduce browser matching overhead or improve native matching throughput; optimization remains incomplete.

## Android numeric-kernel optimization achieved (2026-10-14)

Current SDK default accelerates only Tracker.feedOne numerical costs and global alignment, retaining pinned JS matching/tracking rules and native ONNX/tensors. Float32 rounding/ties and first-update original-column checks preserved; numericKernelVersion dart-f32-callback-v3 and generated script hash guard compatibility. Same-model/core/corpus/public API; iOS remains provisional and deferred.

Decoder-free public SDK profile: idle225731KiB, steady increment145207KiB (141.8MiB), active sampled maximum174870KiB, loading229762KiB. Same-day WebView367959KiB steady gives60.5% saving; original baseline plus charged native overhead gives57.0% saving. Long51.918s audio processed40.221s incl flush (feed38.673s/max737ms). Exact99-snapshot hash retained; all12 broader reference sequences AND progress hashes match saved native evidence, including known mixed-passage omission. No accuracy improvement claim.

Five-minute paced:4.8Msamples/301.530s including1.146sflush, mean336.629/p95653/max677ms, stable681ms maximum completion lag. Five-minute foregroundmic:300.100swall/299.920sPCM/all4798720samples,0errors, sampled outstanding7680samples(one chunk), mean290.606/p95306/max361ms,1.038sflush. Five reset/recreation/disposal cycles passed, no associated renderer; final paired appPSS263123KiB/swap161KiB. Finite sequential samples and observed reclamation do not establish universal peak/leak/low-memory bounds. Temperature profile33..34C; sustained33..34C (see raw samples).

Isolated101-file archive consumer analyzed/built94.1MB, then verified offline: two113:1-5/50progress/388670sample runs, reset/silence/disposal and concurrent16000/8000sample isolation. Public SDK APIs/runtime only; prior verified downloaded assets reused. Phone airplane enabled/Wi-Fi+data off/no current/default network. Android protected AIRPLANE_MODE broadcast denied; supported cmd connectivity airplane-mode succeeded. Original0/1/1 restored and both diagnostics stopped. Private consumer keep-awake guard avoids phone-wide settings.

Package/runtime source hashes match isolated consumer; benchmark PCM/test entry point not in public archive. Dry-run has4 development warnings/no validation errors. Refresh final101-file archive metadata in ignored numeric-v3-archive-summary.json. Root/probe/isolated analyzers, generation pin checks and arm64 builds passed. No commit/push/publication. Android optimization target achieved on this phone; physical iPhone/input-route/native-fault/16KB/low-memory release gates and known recognition limitations remain.

Evidence labels: sdk-numeric-v3-check-20261014-a, sdk-numeric-v3-resources-20261014-a, sdk-numeric-v3-consumer-offline-20261014-a, sdk-numeric-v3-broader-parity-summary.json. Failed hybrid arena and incomplete first kernel run retained only as ignored diagnostics; arena source knobs removed. First callback receiver serialization and generic-wrapper per-byte walks resolved; AOT marker inspection caught a stale same-define build before installation.
