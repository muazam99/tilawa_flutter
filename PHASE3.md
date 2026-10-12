# Phase 3 implementation checkpoint

Date: 2026-10-12. Status: core implementation and Android public-API replay verified; Phase 3 remains in progress for asset fault/recovery and new capture-helper validation. Owner accepted Phase 2 contract and authorized Phase 3 by saying proceed. Phase 1 platform/resource gates remain deferred, not erased.

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
- Microphone route/permission/disconnection/start-stop races and native hardware delivery need platform checks. No arbitrary-rate raw PCM converter or background microphone feature is advertised.
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

## Next bounded Phase 3 work

1. Validate fresh downloader, progress/cancellation/retry, interrupted-stage cleanup and preservation/deletion leases, rather than infer these from bundled-install success.
2. Exercise new microphone helper on Android, including requested/client format evidence, stop/disposal, permission denial and interruption/route recovery. Prior Phase 1 live mic evidence is not proof of the new helper's lifecycle.
3. Check control/overrun/deadline and asset fault paths with owner-authorized verification. No authored test suite currently authorized or added.
4. Repeat the public facade with network disabled, then iPhone when available. Agree resource budgets before permanent runtime selection. No Phase 4/5 transition yet.
