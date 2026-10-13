# Phase 3 implementation checkpoint

Date: 2026-10-12. Status: Android asset lifecycle, isolated facade controls, network-disabled public replay and new helper live/lifecycle/denial/background checks passed. Phase 3 remains in progress for remaining capture/bridge fault and route checks. Owner accepted Phase 2 contract and authorized Phase 3 by saying proceed. Phase 1 platform/resource gates remain deferred, not erased.

## Implemented

- Public development package and pinned Flutter dependencies; immutable typed events/results and runtime-independent adapter factory seam.
- Serialized session feed/reset/terminal operations, admission copying and sample-count-based queue capacity. Terminal result identity, generation/run IDs, batched event validation, final-sequence consistency, interruption deadlines and late-output fencing.
- Source-reviewed Zipformer WebView/WASM adapter with app-owned loopback asset serving. Float32 (not PCM16-requantized) transport. Package runtime code/WASM/notices included; no models/corpus/benchmark audio in SDK assets.
- Local-file SHA-256/size verification; content-addressed bundled/downloaded installs, progress/cancel/retry, atomic activation and stale-stage cleanup. In-process leases/deletion/install coordination, previous valid versions retained.
- Optional foreground record helper, native PCM16-to-float32 conversion, bounded producer, pause/background interruption and explicit disposal. Physical hardware format is not inferred from requested rate; actual delivered-format auditing/route checks remain platform work.
- Optional metadata interface and compatibility/index validation foundation. Complete display mapping/UI and consumer analytics remain Phase 4/consumer work.
- Private SDK probe entry point reuses pinned bundled assets, decodes/resamples the 44.1 kHz WAV externally through local Web Audio, then feeds mono16kfloat32. It uses the public facade without mounting an engine WebView widget; Android behaviour of that integration was verified separately from Phase 1.

## Pending validation / limits

- No authored test suite added or run. Analyzer/build/device outcomes will be recorded below rather than implied by source preparation.
- Cross-isolate/process asset stores are unsupported; use one coordinating Dart isolate. Downloads retry from scratch; byte-range resume is not promised.
- Bundled large AssetBundle files temporarily occupy memory. Default downloadable assets remain separate from SDK archive.
- Runtime teardown uses ORT release plus page replacement/server closure; system WebView object/renderer destruction timing is not a public guarantee. Failed cleanup keeps installation leases rather than permitting deletion during unknown runtime use.
- Microphone route/audio-focus/disconnection/start-stop races and native hardware delivery need additional platform checks; denial/recovery and foreground-background interruption passed on Android below. No arbitrary-rate raw PCM converter or background microphone feature is advertised.
- iOS/Mac verification, extended sustained checks, resource budgets, 16 KB-page runtime and architecture approval remain release gates.

## Verification results

- Root SDK and private consumer app: Flutter analyzer clean. Private consumer arm64 release APK built (76.9 MB including large probe assets plus SDK runtime). This is not the SDK archive size or a store release.
- Source-prepared SDK checkpoint committed as fb2156a before device validation. Follow-up records corrected fixture conversion, binary-integrity checkout attributes and outcomes.
- Physical Infinix X678B/Android 14, unlocked foreground, **online** by owner choice. Installed SDK consumer entry point, no microphone started. Bundled asset installation SHA-256 verification and root package runtime integrity validation succeeded; SDK_READY emitted with local-webview-wasm adapter, without a mounted WebView widget.
- First private replay attempt correctly rejected the fixture's 44.1 kHz format at the probe boundary. Probe changed to the same local Web Audio decode/resample technique used in Phase 1; this is external audio preparation, not hidden resampling in core feed.
- Actual public feed/stop: 388,670 external samples, expected sequence 113:1,113:2,113:3,113:4,113:5; five typed verse matches and 49 typed progress observations. Repeated stop returns identical canonical result; session-ended event carries that same result object.
- Reset created a new run; one-second silence then stop produced an empty final sequence. SDK disposal completed. Store.available reverified/reused the local installation. Probe emitted SDK_COMPLETE without errors on the corrected run.
- The probe's OFFLINE_REUSE log label means local filesystem availability/reuse, not a network-disabled facade run. New SDK was checked while online; Phase 1's prior airplane-mode evidence belongs to the earlier probe. No new acoustic latency/memory/accuracy claim from this check.
- Windows byte integrity: .gitattributes disables text conversion for runtime artifacts, preserving generated SHA-256 values on future Git checkout. Keep vendor notices and binary bytes unchanged.

## Continuation checkpoints

### Phase 3A device checkpoint (2026-10-12)

Physical Infinix X678B/Android 14, online, release build with `PROBE_ASSETS=true`: private `asset_probe.dart` checks completed with ASSET_CHECKS_COMPLETE and SDK_COMPLETE. No authored unit-test suite. Real HTTPS assets/TLS/redirects were used; a private HttpOverrides seam injected initial SocketException failures and slowed response delivery. Storage-only license-text fixtures never entered recognition.

- Real process-kill recovery: first launch downloaded model bytes, logged ASSET_CRASH_READY, then ADB force-stopped the app. Relaunch removed exactly one stale stage. Cancellation after response bytes yielded assetCancelled, no activation and no stale stage.
- Retry recovered after one injected request failure (five total requests for four tiny files, first-file progress attempt 2). Exhaustion with retries=1 stopped at two requests. SHA-256 mismatch was rejected without retry/activation.
- Concurrent bundled installs converged on one verified version; cleanup retained the active stage and deletion during installation returned assetsInUse. Later on-disk corruption was rejected; deleting that version preserved another valid version.
- Fresh pinned download verified all four files (69,246,033 / 5,453,439 / 26,867 / 7,041 bytes), monotonic per-attempt progress and filesystem reuse. Earlier bundled installation was preserved.
- Recognition using downloaded assets repeated 113:1-5, five matches/49 progress, canonical stop/event result identity, reset and empty silence. Session lease blocked deletion while open; deletion succeeded after disposal.
- These checks do not establish mid-response automatic retry, every disk failure or cross-process installation locking. Process termination recovery is cleanup plus fresh restart, not byte-range resume. Connectivity-disabled public facade and new helper outcomes follow below.

### Control and offline checkpoint (2026-10-12)

Release build with `PROBE_CONTROLS=true` and `PROBE_MIC=true`, same physical phone. The private control adapter uses the public factory seam, real session/asset verification and 100 ms interruption/disposal budgets; this is isolated facade evidence, not proof of native/WASM preemption.

- Nonfinite audio rejected; two accepted 16,000-sample feeds filled the outstanding limit; one additional sample rejected without being counted. Admission copying survived caller mutation. Accepted work drained to 32,000 samples before canonical coalesced stop.
- Stalled feed interruption produced incomplete finalization, null sequence and zero processed samples. Reset rejected the quarantined runtime. Injected late transcript was fenced; exactly one session-ended observation and canonical terminal result remained.
- Queued stop then reset rejected competing stop/new input while reset was active, then returned ready with counters cleared. Disposal during stalled feed completed within its bounded path, disposed the adapter once and rejected late feed completion. CONTROL_CHECKS_COMPLETE recorded.
- Airplane mode enabled, Wi-Fi explicitly disabled before launch; Android connectivity reported active default network none/current networks empty. Real local-WebView public replay again recognized 113:1-5 with five matches/49 progress, same stop/event result identity, reset/empty silence/disposal/local reuse and SDK_COMPLETE. Original airplane-off/Wi-Fi-on settings were restored afterward.
- New helper short capture check passed offline: normal five-second capture processed 78,080 samples and canonical complete stop; helper disposed and replacement attached; active three-second capture was disposed by session disposal. No recognition claim from this short ambient-input lifecycle pass.
- Backgrounding during active capture stopped the helper and emitted a complete interruption with 46,080 processed samples; returning to foreground did not restart capture. Explicit reset/start/stop recovered successfully (44,800 samples). HardwareFormatVerified remains false; route/audio-focus/native-format checks still need separate evidence.

### New microphone-helper live and denial checkpoint (2026-10-12)

- Android permission was deliberately revoked and user-fixed denial set for this probe. Start returned microphonePermissionDenied and helper state failed without entering capture. Clearing that temporary flag/restoring the original grant allowed the same helper/session to start and stop successfully (46,080 processed samples). Original USER_SET grant retained; no denial flag remains.
- Owner performed Reset/Start, recited Al-Falaq and tapped Stop using the new helper. The run processed 272,640 samples (17.04 s), emitted five match and 31 word-progress observations, and completed with five sequence entries and canonical repeated-stop identity. Diagnostic logs retain counts only, not exact recognized references; this does not independently establish the five live result references were 113:1-5.
- No capture error/overrun was logged on that live run. Session disposal afterward also disposed the attached helper. The installed 77.0 MB private APK uses sdk_probe.dart with PROBE_CONTROLS/PROBE_MIC; opening it replays diagnostics then presents the helper screen, without automatic capture. Analyzer clean and release build succeeded; no root SDK production-code changes were needed for observed cases.

## Next bounded Phase 3 work

1. Asset lifecycle and mid-response retry/exhaustion/cancel are validated below. Additional disk/network faults remain conditional; do not infer cross-process locking or byte-range resume.
2. Helper capture overload/stalled Stop/control races, native delivered format/audio focus and standalone example denial/background recovery passed below. Next: physical input routes/disconnection and longer sustained resource checks.
3. Controlled bridge/late output/cleanup failures and actual WebView JavaScript bridge fault passed below. Renderer-process death/native teardown failure remain separate checks. No authored unit-test suite added.
4. Network-disabled public facade passed on Android. iPhone remains unavailable; agree resource budgets before permanent runtime selection. Owner later approved committing this checkpoint and proceeding to Phase 4; these remaining Phase 3 gates are deferred, not erased. Phase 5 remains separate.

## Phase 5C Android recovery checkpoint (2026-10-13)

Owner authorized implementation, release builds and control of the connected Infinix X678B/Android14 via ADB/scrcpy. iPhone deferred for now. Baseline73ba68e/master; this recovery work is included in the subsequently owner-requested local5C/Android5D checkpoint. Private diagnostics extend existing opt-in probes, not a new unit-test suite. No runtime bundle/model pins changed.

### Demonstrated defect and repair

Real microphone input feeding a controlled stalled adapter filled a one-chunk producer queue. audioOverrun stopped native AudioRecord, but helper remained stopping/session accepting after2000ms with a400ms interruption deadline: helper awaited the stalled drain before requesting session interruption.

The helper now closes capture continuity, discards unsubmitted buffered PCM and starts session interruption before awaiting shutdown. Normal Stop bounds draining plus the final partial chunk by interruptionDeadline; expiry reports operationTimeout/processingStalled and requests interruption. Disposal discards unsubmitted capture rather than waiting for stalled inference. Helper bindings remain occupied until actual recorder cleanup succeeds; attachment requires a ready/accepting session, and pending interruption blocks Start. Normal successful Stop still drains all submitted capture before session finalization. These deadlines do not establish native OS-call preemption or guaranteed native recorder cleanup.

### Observed results

| Check | Evidence |
|---|---|
| Capture overload/stall | Real native mic plus stalled adapter: audioOverrun, incomplete terminal result/null sequence within bounded path; configured400ms interruption. Late underlying feed released only for diagnostic cleanup. |
| Stop during stalled capture | operationTimeout then incomplete interruption; active helper/session disposal returned while feed still stalled. |
| Rapid controls | Five immediate concurrent Start/Stop cycles, identical coalesced Futures, idle capture after each. Helper replacement rejected during cleanup, accepted afterwards; Dispose during Start interrupted it; reset/new-helper restart and active-session disposal passed. |
| Controlled runtime failure | Public adapter seam emitted bridge loss during stalled feed; feed/reset rejected bridgeDisconnected, late transcript suppressed. |
| Controlled cleanup timeout/failure | disposalFailed; deletion blocked by assetsInUse while cleanup pending or failed. Pending cleanup eventually completed; intentionally failed lease persisted until probe process exit. This is adapter-seam evidence, not native teardown failure evidence. |
| Mid-response download retry | Real HTTPS license-text storage fixtures, partial body then injected SocketException: fresh attempt2,5 requests across4files, full size/hash verification and reusable install. Fixtures never entered recognition. |
| Exhaustion/cancel | Exhaustion2 requests; cancellation1 request after partial bytes. No activation/stale stage, older verified fixture version preserved. No HTTP-range resume or additional cross-process guarantee. |
| Native delivered format | Android activeRecordingConfigurations: client/device16000Hz,1channel,encoding2(PCM16), built-in mic type15, not silenced. Does not claim universal physical hardware format; hardwareFormatVerified remains false. |
| Real Android focus loss | Private competing native transient-exclusive focus request: audioFocusLoss, complete interruption, no capture autorestart on focus release; explicit dispose-helper/reset/new-helper Start/Stop completed. |
| Actual WebView JS bridge fault | Private CDP hook held a feed reply and posted an error through the real TilawaSdk channel. Pending feed/reset rejected bridgeDisconnected; later real-channel transcript fenced; disposal/fresh local runtime and silence stop completed. Not renderer-process crash evidence. |
| Normal runtime regression | Public WebView adapter recognized113:1–5,5matches/49progress,388670samples, same repeated-stop/event result. Reset/one-second silence/empty sequence/disposal/reverified local reuse passed. Online replay, not a new network-disabled claim. |
| Standalone example | Denial/regrant retry, background interruption307200processed/submitted samples/no autorestart, explicit Reset/Start/Stop288000samples complete, disposal/local reopen. Ambient input yielded empty sequences; this does not replace owner live-highlight evidence. |

Root/probe/example analyzers clean; arm64 release builds passed. Combined recovery/control/replay APK77.1MB; actual-bridge-only diagnostic APK76.9MB; standalone example19.0MB. Latest private app was force-stopped, temporary CDP forward removed/debugging disabled. Standalone helper/session disposed, assets retained. Example permission restored to its original granted/USER_SET flags; connectivity remained airplane0/Wi-Fi1/data1. No recorded audio stored/uploaded.

Remaining5C gates: available physical wired/Bluetooth route changes/disconnection (none connected), renderer-process loss and native teardown failure beyond the controlled adapter. Broader passages/sustained resources/budgets/runtime acceptance and intended-platform iPhone validation belong to5D; iPhone deferred, not verified or dropped. See PLAN§16 and prototype/README for reproduction.
