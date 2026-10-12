# Phase 3 implementation checkpoint

Date: 2026-10-12. Status: implementation prepared, validation in progress. Owner accepted Phase 2 contract and authorized Phase 3 by saying proceed. Phase 1 platform/resource gates remain deferred, not erased.

## Implemented

- Public development package and pinned Flutter dependencies; immutable typed events/results and runtime-independent adapter factory seam.
- Serialized session feed/reset/terminal operations, admission copying and sample-count-based queue capacity. Terminal result identity, generation/run IDs, batched event validation, final-sequence consistency, interruption deadlines and late-output fencing.
- Source-reviewed Zipformer WebView/WASM adapter with app-owned loopback asset serving. Float32 (not PCM16-requantized) transport. Package runtime code/WASM/notices included; no models/corpus/benchmark audio in SDK assets.
- Local-file SHA-256/size verification; content-addressed bundled/downloaded installs, progress/cancel/retry, atomic activation and stale-stage cleanup. In-process leases/deletion/install coordination, previous valid versions retained.
- Optional foreground record helper, native PCM16-to-float32 conversion, bounded producer, pause/background interruption and explicit disposal. Physical hardware format is not inferred from requested rate; actual delivered-format auditing/route checks remain platform work.
- Optional metadata interface and compatibility/index validation foundation. Complete display mapping/UI and consumer analytics remain Phase 4/consumer work.
- Private SDK probe entry point reuses pinned bundled assets and feeds mono16kPCM16 WAV as external float32 input. It uses the public facade without mounting an engine WebView widget; runtime behaviour of that integration is being checked separately from Phase 1.

## Pending validation / limits

- No authored test suite added or run. Analyzer/build/device outcomes will be recorded below rather than implied by source preparation.
- Cross-isolate/process asset stores are unsupported; use one coordinating Dart isolate. Downloads retry from scratch; byte-range resume is not promised.
- Bundled large AssetBundle files temporarily occupy memory. Default downloadable assets remain separate from SDK archive.
- Runtime teardown uses ORT release plus page replacement/server closure; system WebView object/renderer destruction timing is not a public guarantee. Failed cleanup keeps installation leases rather than permitting deletion during unknown runtime use.
- Microphone route/permission/disconnection/start-stop races and native hardware delivery need platform checks. No arbitrary-rate raw PCM converter or background microphone feature is advertised.
- iOS/Mac verification, extended sustained checks, resource budgets, 16 KB-page runtime and architecture approval remain release gates.

## Verification results

Pending at source-prepared checkpoint.
