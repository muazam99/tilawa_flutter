# Plan: Tilawa Flutter SDK

**Status:** Phase 0 complete. Phase 1 partial: Android release recognition/lifecycle smoke evidence recorded; iOS and remaining acceptance checks outstanding.
**Created:** 2026-10-12
**Last updated:** 2026-10-12
**Package working name:** `tilawa_flutter`
**Components:** Independent public Flutter SDK, standalone example app, future Qiyam consumer.
**Initial platforms:** Android and iOS 16+.
**Current phase:** Phase 1, bridge feasibility prototype.

## 1. Goal

Build a public Flutter SDK that makes Tilawa's offline Quran recognition accessible through an idiomatic Dart API. Developers should be able to find a recited passage, follow word progress, and consume documented recognition observations to build their own experiences and analytics.

Publish the package on pub.dev and consume the same public API in Qiyam. This is a reusable library: Qiyam must not receive a private implementation path or dictate the SDK's state management, UI, storage, or analytics rules.

This document is the portable implementation and handoff reference. A new session should read it before investigating or coding. Keep the phase status and resume notes current instead of creating a competing plan.

## 2. Owner-approved decisions

| Decision | Agreed direction |
|---|---|
| Distribution | Public Flutter package on pub.dev, also used by Qiyam |
| Working name and folder | `tilawa_flutter`; name availability and final branding still need checking |
| Platforms for the first release | Android and iOS |
| Minimum iOS version | iOS 16 accepted |
| First release priority | Finding and following recitation |
| Correction | Later extension through the same session/event architecture |
| Analytics boundary | SDK passes observations; consuming applications calculate and persist analytics |
| Page support | Make page-based analytics possible through optional developer-provided metadata mapping |
| Repeated recitation | Expose the available observations; applications define repeat-counting policy |
| Qiyam pricing | Tilawa-powered recognition/correction features always free |
| Reusability | Flexible extension points and a UI/state-management-independent Dart API |
| Phase order | Feasibility, public API, audio/assets, tracking/metadata, example/release validation |

The bridge is the preferred feasibility candidate, not a verified or permanently selected architecture. No runtime dependency, native adapter, public API signature, package license, or performance target has been finalized.

## 3. What Tilawa provides

Upstream: <https://tilawa.dev/> and <https://github.com/yazinsai/tilawa>.

Research on 2026-10-12 inspected the repository's `@tilawa/core`, whose package metadata identifies version `0.4.0`. The tree lookup resolved `main` to `2f2617460dc4a6b967e0cc49fa04804bbf22ec69`; individual source reads used `main`. Phase 1 must explicitly pin and review one reproducible baseline. The npm publication status was not independently checked.

The core is TypeScript with an injected ONNX runtime seam. Flutter cannot directly consume the npm package on native mobile platforms. Its pipeline includes more than model inference:

```text
Mono 16 kHz audio
  -> audio preprocessing / Kaldi filterbank
  -> streaming ONNX inference
  -> CTC phoneme decoding
  -> Quran search and alignment
  -> tracking / correction logic
  -> recognition events
```

Loading the ONNX model alone does not reproduce Tilawa's behaviour.

### Engines and assets

| Engine | Characteristics | Assets identified during research |
|---|---|---|
| Zipformer | Default streaming phoneme engine; current correction features | Approximately 66 MB `zipformer_a0w_ep1_a05.int8.onnx`, approximately 5.5 MB `zipformer_quran.json`, optional Quran display text |
| FastConformer | Alternate text-CTC engine; one-shot and streaming APIs | Approximately 88 MB model plus vocabulary, CTC-token mapping and Quran text |

Zipformer is the initial feasibility target. Supporting another engine does not imply identical tracking, transcript, or correction capabilities. Default model file size is not runtime memory usage or total application-size overhead.

### Developer-facing capability surface

- Recognition sessions: `feed`, `stop` / `flush`, `reset`.
- Verse candidates, verse matches, word progress, transcript updates, final verse sequences.
- Zipformer session state, transcript, tallies, verses and configuration.
- Correction mode, expected passage, correction actions and structural-rule settings.
- Optional diagnostics and word verdicts.
- Low-level exported search, decoding, alignment and other engine utilities.

Long-term parity means documented application-level capabilities. Exposing every internal helper is not an initial commitment. Record supported capabilities per engine and platform.

## 4. Architecture options and provisional recommendation

### A. Bridge to the upstream JavaScript core

Compile/bundle upstream TypeScript locally and expose a Dart facade. Two candidate implementations are:

1. Embedded JavaScript runtime plus a native ONNX adapter.
2. Local WebView/browser environment plus JavaScript and ONNX WebAssembly.

Both must operate locally after asset setup. A bridge must not depend on opening the hosted Tilawa website, a remote script CDN at inference time, or uploading recitation audio.

Advantages: reuse the original decoding/tracking logic, preserve upstream behaviour, and adopt upstream changes without translating an entire engine.

Questions to prove: typed arrays and BigInt/int64 support, asynchronous session calls, tensor transfer and ownership, native inference integration, JSON/module bundling, lifecycle behaviour, binary size, latency and memory. BigInt64Array support is explicitly required by the upstream JavaScript model adapter. Native ONNX adapters must preserve appropriate int64 tensor types.

A WebView candidate additionally needs proof of local asset serving/loading, WASM availability and permissions/lifecycle behaviour. Native audio feeding versus browser microphone capture is an implementation choice, not a settled fact.

### B. Dart port plus native ONNX

Translate preprocessing, decoding, Quran matching, alignment, tracking and correction code into Dart while reusing the existing trained model.

Advantages: no embedded JavaScript runtime, direct control of Dart integration and scheduling.

Costs: substantially more implementation and numerical/state parity work; upstream changes must be reviewed and translated. No new model training is inherently required, but a Dart port is not automatically faster or equivalent.

### C. Hosted inference

A server could run Tilawa, but it would change the offline/on-device premise and require network audio transfer. It is outside the agreed first-release direction.

### Recommendation

Evaluate the bridge candidates first and keep the public Dart facade independent of their implementation. Select an architecture only after meaningful Android/iOS feasibility evidence. If the bridge is unsuitable, document the finding and obtain owner agreement before expanding into a Dart port.

Do not start by publishing a wrapper that has only demonstrated model loading.

## 5. First-release SDK responsibilities

### Session and engine integration

- Initialize an engine with a compatible model/corpus combination.
- Accept and process audio in order.
- Emit typed, immutable observations through standard Dart streams.
- Provide documented session state and final results.
- Define stop/flush, reset and disposal semantics.
- Serialize inference and control operations, including changes during an in-flight feed.
- Expose supported configuration without leaking platform runtime objects into the ordinary API.

### Audio input

- Core input: explicitly documented mono 16 kHz float32 PCM contract, including amplitude range and ownership/copying rules.
- Allow applications to feed externally captured audio.
- Provide an optional microphone helper or clearly separable convenience layer.
- Convert supported capture formats correctly; do not assume a requested 16 kHz recording rate is always delivered by hardware.
- Handle resampling, channel conversion, chunking and incomplete PCM samples as applicable.
- Bound audio buffering and report processing overruns. Do not silently discard audio or grow an unlimited queue.
- Define behaviour for microphone denial, interruptions, route changes and disconnection.
- Proposed first-release policy: foreground recognition, with explicit interruption/background handling. Background recognition is not approved scope.

### Model and asset handling

- Support developer-supplied local files, bundled assets and configurable downloads.
- Keep large model/corpus files separate from the pub.dev archive by default.
- Use versioned manifests that identify compatible model, corpus, vocabulary, I/O schema and engine versions.
- Include meaningful file integrity verification and safe installation of completed downloads.
- Expose progress, cancellation, retry/recovery, asset availability and deletion.
- Ensure partial downloads never masquerade as usable assets.
- Permit offline initialization and recognition after setup.
- Bundle any required JavaScript/runtime resources appropriately; consumers should not need manual npm setup to use the released mobile package.
- Define asset storage and update policy, including how an existing valid version survives an interrupted replacement.

### Metadata extension

- Accept an optional developer-supplied resolver for compatible Quran display text and word/page/juz references.
- Recognition must remain usable without display metadata.
- Identify the recognition corpus/version so mappings can be checked for compatibility.
- Report mapping mismatches explicitly instead of producing incorrect highlights.

## 6. Public API and event contract

Names below are proposals, not final signatures.

| Observation | Intended information |
|---|---|
| Session state | Initializing, ready, listening, stopped/interrupted, failure as appropriate |
| Verse candidate | Ranked candidate references and upstream score/confidence |
| Verse match | Surah, ayah, confidence, optional text/context |
| Word progress | Surah, ayah, current index, total words, matched indices |
| Transcript update | Text plus representation, since Zipformer produces phonemes rather than an ordinary Arabic transcript |
| Final sequence | The upstream recognized verse sequence and associated confidence |
| Diagnostics | Opt-in engine state/details |
| Error | Structured error category/code and useful details |

Consider session ID, ordered event sequence number, emission time and processed-audio position as facade metadata. Define their precision and origin. Emission time is not an exact acoustic word timestamp; a processed-audio position is not a word boundary unless established by the engine.

The contract must document:

- Surah/ayah numbering and word-index base.
- Ayah-local indices versus corpus-global indices.
- Whether progress is a snapshot, an incremental observation or a revision.
- Duplicate events, revised recognition and candidate-to-match transitions.
- What matched indices actually mean according to upstream emission logic.
- Ordering, queueing, late-event handling and session ownership.
- What stop flushes, when it completes, and how callers obtain the final result.
- What reset clears versus retains; whether model/runtime resources are reused.
- Resource release and ownership of externally supplied adapters.
- How unsupported features are reported.
- Stream subscription/disposal behaviour and a single source of truth for result delivery.
- Unknown/future event handling and versioned serialization if serialization is exposed.

Keep the high-level API independent of GetX, Riverpod, Bloc, Qiyam's result wrappers, Supabase and a particular native ONNX package. Prefer useful extension points over arbitrary unvalidated configuration.

## 7. Analytics boundary and page mapping

The owner explicitly corrected the earlier discussion: this is a public library that passes data. The consuming frontend/application decides how to aggregate, display and persist analytics.

Qiyam's desired examples include reading minutes, recognized ayahs, word coverage, session history, last-read position and page counts. These are consumer use cases, not SDK completion/reward policies.

### Semantics applications need

- A verse match is recognition evidence, not proof that every word was read. Upstream's default verse-emission gate is approximately half of the ayah's words.
- Cursor advancement does not prove that intervening words were recited.
- Confidence is an engine score, not a calibrated probability of correct recitation.
- Microphone-on time, elapsed session time and active recitation time are different measures. Speech-activity-derived time requires a defined and validated method.
- Repeated progress messages must not be mistaken for newly read words.
- Unique word coverage and repeated reading activity are different quantities.
- The upstream session suppresses some duplicate verse emissions and accumulates some tallies. Its final sequence is not guaranteed to be a chronological log of every repeated reading pass.
- A wrapper must not fabricate occurrence events or repeat counts that the available evidence cannot establish. Investigate richer observations if required and expose their limitations.

### Page and juz support

Resolve `(surah, ayah, word index)` through developer-provided metadata. Page numbering depends on the Quran edition/layout.

- Ayah-level mapping can identify pages associated with recognized ayahs.
- Word-level mapping supports more precise coverage and ayahs crossing page boundaries.
- A page containing one matched word, a partially covered page and a fully covered page are different facts.
- Avoid a built-in ambiguous `pagesRead` counter. Expose references/observations so applications choose the definition.
- Compatible text/layout mapping does not make the model support arbitrary riwayat, corpora or replacement model formats.

Persistence, accounts, synchronization, streaks, repeat-credit policy, charts, rewards and full-page completion decisions belong to consumers. Examples may illustrate aggregation but must label their assumptions and remain replaceable.

## 8. Qiyam integration context

Source-only inspection found the Quran worktree's entities in `mosque_tracker_quran/lib/modules/quran_module/entities/quran_entities.dart`.

- `QuranWord` identifies words by surah, ayah and `positionInAyah`.
- Qiyam positions are 1-based; upstream engine word positions are 0-based.
- `QuranAyah.words` includes ayah-end markers; `textWords` excludes them.
- The worktree has Quran assets, page/juz metadata and playback infrastructure.
- The inspected worktree Podfile targets iOS 14; the owner has now accepted iOS 16 for this SDK. Actual Qiyam target changes must be reviewed when integration is requested.

Use these facts for a future consumer adapter, not as SDK dependencies. Recheck the active Qiyam checkout and current source before implementation. Display-only bismillah, end markers and segmentation require explicit mapping.

Qiyam should consume the same exported SDK interfaces as the standalone example and other applications. Its integration and analytics UI are a separate feature task, not authorization to edit the app/API/database during SDK development.

## 9. Licensing and attribution

Research reviewed upstream `NOTICE.md` and the full NPL-1.2 text.

| Component | Terms identified |
|---|---|
| Tilawa repository/package code | MIT, subject to its stated asset exceptions |
| Default Zipformer model and phoneme corpus | Quran-Lab NPL-1.2 |
| Zipformer vocabulary and other derived artifacts | NPL-1.2 exceptions documented in upstream NOTICE |
| Alternate FastConformer path | Repository code/assets and NVIDIA model have separate terms, including CC-BY-4.0 |

NPL-1.2 prohibits charging for the work or powered features, including paywalls, subscriptions and advertising revenue on those features. Hosted use is free or qualifying cost recovery only. Derivatives have share-alike requirements, and the license file must accompany distribution. The license says no commercial license to charge will be granted.

The owner confirmed Qiyam's Tilawa-powered features will always be free. Public consumers must still receive clear license information. A free wrapper, a download instead of bundling, a native port, or use in an otherwise monetized app does not erase an asset's conditions. Unrelated paid features are distinguished in the NPL text; do not generalize it into a ban on all unrelated income.

Before distributing the SDK:

- Inventory copied/bundled/generated code, vocabulary, JSON indices, model/corpus files and native dependencies.
- Preserve MIT notices and all applicable third-party licenses.
- Check the licensing of bundled artifacts even when imported through a code package; do not label everything MIT merely because the repository/package says MIT.
- Verify FastConformer asset provenance/attribution before advertising it as a commercially usable alternative. Correction parity is not established.
- Choose the license for our authored wrapper after the artifact inventory. Wrapper license remains undecided.
- Describe upstream credit and independent-maintainer status accurately. Do not claim an official Tilawa Flutter package without upstream agreement.

## 10. Recognition/correction limits

The initial release is recognition/tracking. Recognition success does not certify recitation correctness, and no flag does not prove no mistake occurred.

Upstream reports strong recognition results on specific benchmarks, including 53/53 on v1 and 56/58 on held-out multi-ayah windows. These are upstream reports, not independently verified Flutter accuracy claims.

Correction is conservative practice assistance. Current upstream changelog reports approximately 0.203 recall without an expected passage on one acted-mistake evaluation and approximately 0.436 F1 with an expected passage. Those figures are dataset/model/configuration-specific and must not be treated as general accuracy guarantees.

Later correction work should expose the upstream distinctions and lifecycle:

- Possible omission, substitution, vowel difference and repetition.
- Possible skipped ayah versus unclear ayah.
- Soft repetition notes versus interrupting issues.
- Retry, stop retry, dismiss, review later, continue and close.
- Expected passage, structural rules and diagnostic word verdicts.
- Structural timing defaults to stop; pause timing is optional and has different false-flag tradeoffs.
- Slip-head and other experimental/opt-in behaviour must retain that status.

No full tajweed grading, certified assessment, universal mistake detection or Tarteel-level parity claim is justified. Read the pinned source alongside documentation: some upstream prose describes older behaviour, such as omission thresholds, while current source/changelog includes partial omissions.

## 11. Dependency and maintenance policy

- Pin the initial upstream code/model/corpus baseline. Keep a compatibility record and deliberately review updates.
- Verify actual runtime support, required ONNX operators, tensor types/cache states, CPU execution and native build integration.
- `flutter_onnxruntime` was researched as a candidate, not selected. Its current documentation requires iOS 16 and static linkage, and lists platform-specific limitations.
- Android minimum version, CPU architectures, Dart/Flutter minimum versions and final dependency constraints remain open until feasibility review.
- Include Android native-library/page-size compatibility and release-mode integration in platform evaluation.
- Do not advertise desktop/web support solely because a dependency lists those platforms.
- Avoid a package structure with many public subpackages unless a proven implementation need justifies it. Logical layer separation can initially live in one package.
- A future Git repository, publisher domain, package-name availability, hosting location and release automation remain undecided.

## 12. Phases

### Phase 0: Discussion and portable handoff (completed)

Deliverable: this plan, the project folder and durable cross-session memory.

Acceptance: agreed scope/platform/licensing intent and provisional architecture are distinguished from unverified feasibility; next session has a clear starting point. No SDK scaffold or runtime verification is implied.

### Phase 1: Prove the Android/iOS bridge (in progress)

1. Read this plan and inspect local status/instructions.
2. Pin and review the exact upstream baseline and artifact licenses.
3. Check for existing maintained Flutter integrations before duplicating work; the earlier package-name API lookups alone were not a comprehensive ecosystem search.
4. Compare embedded-JavaScript/native-ONNX and local-WebView/WASM candidates against Android/iOS 16, typed arrays, BigInt/int64, async operation, assets and threading requirements.
5. Select a minimal candidate prototype. Use local audio input and a small debugging/example surface, not Qiyam UI.
6. Demonstrate actual inference followed by verse matching and word progress with the pinned assets.
7. With owner authorization, evaluate Android and iPhone behaviour, latency, sustained processing, resource usage, silence, stop/reset/disposal and offline operation.
8. Record implementation choice, evidence, limitations and fallback decision.

Acceptance: meaningful end-to-end evidence on both supported platforms, including recognition events, not model loading alone. If iOS/device verification is unavailable, record partial status rather than call feasibility complete. Quantitative targets should be agreed using measured results.

### Phase 2: Finalize the public Dart API (pending)

Define immutable events, session methods/state, audio contract, adapter interfaces, configuration, error categories, supported capabilities, metadata resolver and lifecycle/ownership semantics.

Explicitly examine upstream duplicate suppression, progress semantics, lost tracking, transcript representation, flush/reset behaviour and whether available observations support repeated-reading analytics.

Acceptance: reviewed public contract with examples for raw audio, event subscription and optional metadata. Ordinary consumers do not depend on Qiyam or runtime internals. Unsupported/uncertain capabilities are documented.

### Phase 3: Implement audio and asset handling (pending)

Implement the approved engine adapter, serialized processing, bounded queues, input conversion and optional microphone convenience. Add versioned/local/bundled/downloaded asset loading, integrity checks, cancellation/recovery and resource lifecycle.

Acceptance: usable documented audio/asset paths; offline reuse; predictable failure/overrun/interrupt behaviour; correct cleanup. Perform authorized verification appropriate to the selected implementation and record actual outcomes.

### Phase 4: Complete tracking and metadata mapping (pending)

Wire the full first-release typed recognition stream and final results. Implement optional compatible text/word/page/juz mapping, mismatch handling and a clear data contract for consumer analytics.

Acceptance: standalone Flutter consumer can find recitation and follow words using the public API. Compatible page references can be derived without hardcoding a page layout or completion policy. Review against pinned upstream observations, including repetitions, ambiguous verses, silence, restarts and late results where supported.

### Phase 5: Validate the example and prepare pub.dev release (pending)

Build a standalone example showing setup, live recognition, word progress and optional metadata. Illustrate consumer-owned analytics with clearly labelled assumptions. Prepare README, API documentation, CHANGELOG, license/NOTICE inventory, supported-platform matrix and release metadata.

With explicit authorization, validate release-mode Android/iOS integration, real-device/offline behaviour, relevant parity/performance checks and a pub.dev dry run. Confirm the published archive includes necessary local bridge resources and notices while excluding large default model assets and development artifacts.

Acceptance: recorded platform evidence, reproducible setup, accurate capability/license documentation, chosen package/publisher details and a clean publication dry run. Actual publication requires a separate explicit request. Qiyam integration remains a consumer follow-up.

### Later extension: Correction parity (not started, outside initial release)

Use the established session/event model to add supported correction and retry workflows. Reassess API/source/assets and expose engine-specific capabilities. This is a later scoped plan, not permission to implement it while doing recognition/tracking.

## 13. Current phase and resume notes

**Current phase:** Phase 1 partial, paused for a new session at the owner's request. See `prototype/FEASIBILITY.md` for the bounded comparison and recorded evidence.

As of 2026-10-12:

- The owner approved the public SDK scope, Android/iOS targets, iOS 16 minimum and five-phase order.
- The owner wants analytics observations, including page-mapping support; applications own aggregation/persistence and repeat-counting rules.
- Phase 0 handoff reconfirmed. Phase 1 source/assets pinned in `prototype/baseline.json`; source Git blobs and model/corpus/I/O/license SHA-256 verified during setup. A private Flutter WebView/WASM probe and local runtime bundle are prepared.
- No dedicated Git repository has been initialized and no publication action has been taken.
- Architecture remains provisional; investigate the bridge candidates before declaring native/Dart/WebView choices settled.
- Read the source links below when needed. Do not restart the product discussion or infer full functionality from the homepage.
- Owner authorized setup, dependency installation, downloads and validation using the connected real phone (no Android emulator). Debug and arm64 release APKs built and ran on Infinix X678B/Android 14. The release probe matched 112:1 and 113:1-5 with word progress; silence/reset/stop/dispose/reinitialize smoke checks completed. See `prototype/FEASIBILITY.md` for measurements and limitations.
- Foreground release multi-ayah replay processed 24.292 s input in 12.805 s; paced replay finished in 25.164 s including flush. WebView cannot enable threaded WASM on the inspected device. Separate app/renderer memory snapshots were approximately 324/302 MiB, so footprint needs further review.
- Next: microphone/hardware-format and network-disabled checks, agreed resource/performance targets and physical-iPhone verification on Mac/Xcode. These remain outstanding; no Phase 2 API finalization was started.
- Owner personally tested the installed prototype and reported enthusiastic success and quick recognition. The exact test scenario was not specified; this is positive owner feedback, not completion of every microphone/offline/lifecycle gate.

### Next-session handoff

1. Read this plan, `prototype/FEASIBILITY.md` and `prototype/README.md`; check the working tree and reconnect the actual phone before any device operations. Resume the existing prototype rather than rebuilding the product discussion or assuming a public SDK already exists.
2. The app `Tilawa Bridge Probe` (`dev.qiyam.tilawa_bridge_probe`) is installed on the owner's Infinix. The last installed arm64 release build uses `PROBE_AUTORUN=true` and `PROBE_THREADS=4`; opening a fresh app instance automatically runs the probes, with threads falling back to one. It keeps its own foreground Android window awake. No microphone recording was left running by the agent.
3. Start with the remaining Android checks: confirm the owner's tested scenario, inspect/verify native microphone format and sustained feeding, then network-disabled initialization/recognition and interruption/route behaviour. Agree measurable resource/performance targets and measure memory across repeated sessions.
4. Physical-iPhone verification requires Mac/Xcode. Keep Phase 1 partial until both-platform acceptance is established; advance to Phase 2 only after the owner agrees the phase transition.

Reproducible assets/source are pinned in `prototype/baseline.json`; npm and Flutter lockfiles are saved. Downloaded source, model/corpus and generated runtime/build products are ignored by Git. The local release APK is at `prototype/app/build/app/outputs/flutter-apk/app-release.apk` and can be regenerated using the prototype README. No commits, remote repository, publication or Qiyam integration occurred.

### Working permissions and boundaries

- Original handoff authorized planning only. On 2026-10-12 the owner additionally authorized Phase 1 setup and validation on the connected physical Android phone; this does not authorize later-phase execution or publication.
- No Android emulator requested. iOS runtime verification is not available in the current Windows environment.
- Do not add or modify tests unless the owner explicitly requests them. Verification design remains necessary, but test authoring/execution needs permission.
- Do not commit, push, create remote repositories or publish to pub.dev without explicit authorization.
- Preserve unfamiliar existing files and changes. Check the active checkout before editing.
- Keep Qiyam integration separate; this task authorizes no app/API/database edits.
- Save a checkpoint after each meaningful phase, distinguishing source-prepared work from actual runtime evidence.

## 14. Decisions log

- 2026-10-12: Public SDK plus Qiyam consumer approved. Reusable observations and extension points take precedence over application-specific analytics rules.
- 2026-10-12: Android/iOS first and iOS 16 minimum approved. Other platforms require later verified support.
- 2026-10-12: Finding/following recitation first; correction deferred. Preserve an extensible API for later correction workflows.
- 2026-10-12: Page-based analytics should be possible through optional compatible Quran metadata; consumer defines what counts as a read page.
- 2026-10-12: Qiyam's powered features always free. Public SDK documentation must still explain separate model/corpus terms.
- 2026-10-12: Owner approved feasibility -> API -> audio/assets -> tracking/metadata -> example/release phase order. Bridge architecture stays provisional until verified.

## 15. Source references

- Website: <https://tilawa.dev/>
- Repository/README: <https://github.com/yazinsai/tilawa>
- Core metadata: <https://github.com/yazinsai/tilawa/blob/main/packages/core/package.json>
- Main API: <https://github.com/yazinsai/tilawa/blob/main/packages/core/src/index.ts>
- Event types: <https://github.com/yazinsai/tilawa/blob/main/packages/core/src/types.ts>
- Recitation exports: <https://github.com/yazinsai/tilawa/blob/main/packages/core/src/recitation/index.ts>
- Zipformer session: <https://github.com/yazinsai/tilawa/blob/main/packages/core/src/recitation/session.ts>
- Correction source: <https://github.com/yazinsai/tilawa/blob/main/packages/core/src/recitation/correction.ts>
- Correction documentation: <https://github.com/yazinsai/tilawa/blob/main/docs/live-correction.md>
- Core changelog: <https://github.com/yazinsai/tilawa/blob/main/packages/core/CHANGELOG.md>
- React Native runtime-injection example: <https://github.com/yazinsai/tilawa/blob/main/packages/core/examples/react-native.md>
- Third-party notices: <https://github.com/yazinsai/tilawa/blob/main/NOTICE.md>
- NPL-1.2: <https://github.com/yazinsai/tilawa/blob/main/licenses/NPL-1.2.txt>
- Candidate ONNX plugin: <https://pub.dev/packages/flutter_onnxruntime>
- pub.dev publication guidance: <https://dart.dev/tools/pub/publishing>
- Phase 1 pinned code baseline: <https://github.com/yazinsai/tilawa/tree/2f2617460dc4a6b967e0cc49fa04804bbf22ec69>
- Pinned asset URLs/checksums: `prototype/baseline.json`; runtime/plugin references and results: `prototype/FEASIBILITY.md`.

The original research links track upstream `main` unless versioned. Phase 1 uses the pinned baseline above; do not silently substitute newer `main` files or model assets when resuming.
