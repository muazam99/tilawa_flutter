# Plan: Tilawa Flutter SDK

**Status:** Phase5A/5B saved in local commit73ba68e. This owner-requested local checkpoint on master follows73ba68e and saves Phase5C recovery and5D Android broader/sustained/resource evidence recorded on2026-10-13. Mixed-passage omissions and material renderer recreation footprint remain acceptance items. Physical routes/renderer/native teardown, iPhone (deferred), final runtime/resource acceptance and5E–G remain open. No push, dry run or publication.
**Created:** 2026-10-12
**Last updated:** 2026-10-13
**Package working name:** `tilawa_flutter`
**Components:** Independent public Flutter SDK, standalone example app, future Qiyam consumer.
**Initial platforms:** Android and iOS 16+.
**Current phase:** Phase5D Android evidence collected; final intended-platform/recognition/resource/runtime acceptance pending. See sections13/16, PHASE3.md and prototype/FEASIBILITY.md.

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

### Phase 1: Prove the Android/iOS bridge (Android checkpoint accepted; platform gates deferred)

1. Read this plan and inspect local status/instructions.
2. Pin and review the exact upstream baseline and artifact licenses.
3. Check for existing maintained Flutter integrations before duplicating work; the earlier package-name API lookups alone were not a comprehensive ecosystem search.
4. Compare embedded-JavaScript/native-ONNX and local-WebView/WASM candidates against Android/iOS 16, typed arrays, BigInt/int64, async operation, assets and threading requirements.
5. Select a minimal candidate prototype. Use local audio input and a small debugging/example surface, not Qiyam UI.
6. Demonstrate actual inference followed by verse matching and word progress with the pinned assets.
7. With owner authorization, evaluate Android and iPhone behaviour, latency, sustained processing, resource usage, silence, stop/reset/disposal and offline operation.
8. Record implementation choice, evidence, limitations and fallback decision.

Acceptance: meaningful end-to-end evidence on both supported platforms, including recognition events, not model loading alone. If iOS/device verification is unavailable, record partial status rather than call feasibility complete. Quantitative targets should be agreed using measured results.

Owner-approved progression on 2026-10-12: current Android evidence is sufficient to begin Phase 2 API design. Both-platform feasibility is not declared complete. iPhone verification and deferred Android/resource checks remain mandatory validation/release gates; architecture stays provisional.

### Phase 2: Finalize the public Dart API (design checkpoint accepted)

Define immutable events, session methods/state, audio contract, adapter interfaces, configuration, error categories, supported capabilities, metadata resolver and lifecycle/ownership semantics.

Explicitly examine upstream duplicate suppression, progress semantics, lost tracking, transcript representation, flush/reset behaviour and whether available observations support repeated-reading analytics.

Acceptance: reviewed public contract with examples for raw audio, event subscription and optional metadata. Ordinary consumers do not depend on Qiyam or runtime internals. Unsupported/uncertain capabilities are documented.

Deliverable: `API_CONTRACT.md`, source-reviewed against the pinned ZipformerSession and emission code. It specifies audio copying/backpressure, session/control lifecycle, immutable typed events, canonical completion, capabilities/config/errors, adapter ownership, separate microphone and metadata layers, source limitations and consumer examples. Owner subsequently approved proceeding to Phase 3; source implementation and validation limits are tracked separately.

### Phase 3: Implement audio and asset handling (Android checkpoint accepted; remaining gates deferred)

Implement the approved engine adapter, serialized processing, bounded queues, input conversion and optional microphone convenience. Add versioned/local/bundled/downloaded asset loading, integrity checks, cancellation/recovery and resource lifecycle.

Acceptance: usable documented audio/asset paths; offline reuse; predictable failure/overrun/interrupt behaviour; correct cleanup. Perform authorized verification appropriate to the selected implementation and record actual outcomes.

Implementation/checkpoint: `PHASE3.md`, public development package under `lib/`, bundled runtime JS/WASM/notices under `assets/runtime`, large assets installed separately. Private public-API validation surface: `prototype/app/lib/sdk_probe.dart`. No Phase 4/5 transition is implied.

### Phase 4: Complete tracking and metadata mapping (implementation/Android checkpoint complete)

Wire the full first-release typed recognition stream and final results. Implement optional compatible text/word/page/juz mapping, mismatch handling and a clear data contract for consumer analytics.

Acceptance: standalone Flutter consumer can find recitation and follow words using the public API. Compatible page references can be derived without hardcoding a page layout or completion policy. Review against pinned upstream observations, including repetitions, ambiguous verses, silence, restarts and late results where supported.

Checkpoint: private tracking_probe.dart consumes only exported SDK interfaces and developer metadata. Session binds resolver edition/version at open and rejects empty/invalid word rows. Isolated source-compatible diagnostics passed repeated/revised snapshots, lost/sample-state distinction, uncalibrated scores, immutable payloads, terminal ordering, 17 metadata mismatches/resolver failure and stale lookup/reset guards. Real Android runtime validated nine fixture ayahs/38 words, tracked113 twice with duplicate match suppression, then located112:1; owner confirmed live word following. Corpus plain labels and verified page604/juz30 references are a limited developer fixture, not a universal mapping or correctness/accuracy assessment. Actual lost/relocated acoustic coverage and deferred platform/resource checks are not implied. Phase5 example/release work remains separate.

### Phase 5: Validate the example and prepare pub.dev release (5A/5B complete; 5C checkpoint verified)

Build a standalone example showing setup, live recognition, word progress and optional metadata. Illustrate consumer-owned analytics with clearly labelled assumptions. Prepare README, API documentation, CHANGELOG, license/NOTICE inventory, supported-platform matrix and release metadata.

With explicit authorization, validate release-mode Android/iOS integration, real-device/offline behaviour, relevant parity/performance checks and a pub.dev dry run. Confirm the published archive includes necessary local bridge resources and notices while excluding large default model assets and development artifacts.

Acceptance: recorded platform evidence, reproducible setup, accurate capability/license documentation, chosen package/publisher details and a clean publication dry run. Actual publication requires a separate explicit request. Qiyam integration remains a consumer follow-up.

### Later extension: Correction parity (not started, outside initial release)

Use the established session/event model to add supported correction and retry workflows. Reassess API/source/assets and expose engine-specific capabilities. This is a later scoped plan, not permission to implement it while doing recognition/tracking.

## 13. Current phase and resume notes

**Current phase:** Phase5D Android evidence collected on2026-10-13 after owner-approved5C/Android5D progression. Eight pinned clips/five derived cases, five-minute paced input, five-minute foreground mic and five recreation/reset/disposal cycles completed. Standalone/noisy/partial/silence cases behaved as expected; two compound switches omitted references and remain documented limitations. Sustained processing kept up/no capture errors, but renderer recreation sample853740KiB PSS requires explicit resource/runtime acceptance. iPhone deferred for now; physical route/disconnection/renderer/native teardown, intended-platform/resource acceptance and5E–G gates remain open. This owner-requested local checkpoint saves source/diagnostics/docs on master following73ba68e; no push/dryrun/publication.

As of 2026-10-12:

- The owner approved the public SDK scope, Android/iOS targets, iOS 16 minimum and five-phase order.
- The owner wants analytics observations, including page-mapping support; applications own aggregation/persistence and repeat-counting rules.
- Phase 0 handoff reconfirmed. Phase 1 source/assets pinned in `prototype/baseline.json`; source Git blobs and model/corpus/I/O/license SHA-256 verified during setup. A private Flutter WebView/WASM probe and local runtime bundle are prepared.
- Dedicated local Git repository initialized with owner approval during continuation; initial Phase 1 checkpoint is `f981d91`. No remote/push or publication action has been taken.
- Architecture remains provisional; investigate the bridge candidates before declaring native/Dart/WebView choices settled.
- Read the source links below when needed. Do not restart the product discussion or infer full functionality from the homepage.
- Owner authorized setup, dependency installation, downloads and validation using the connected real phone (no Android emulator). Debug and arm64 release APKs built and ran on Infinix X678B/Android 14. The release probe matched 112:1 and 113:1-5 with word progress; silence/reset/stop/dispose/reinitialize smoke checks completed. See `prototype/FEASIBILITY.md` for measurements and limitations.
- Foreground release multi-ayah replay processed 24.292 s input in 12.805 s; paced replay finished in 25.164 s including flush. WebView cannot enable threaded WASM on the inspected device. Separate app/renderer memory snapshots were approximately 324/302 MiB, so footprint needs further review.
- Continuation established Android delivered/client and device-side mono 16 kHz PCM16 format, offline fresh/warm initialization/replay and a 125-second live pass. Longer sustained capture, permission/interruption/route checks, resource targets and physical-iPhone verification remain deferred gates. Owner approved Phase 2; its public contract draft is saved for review.
- Owner confirmed the earlier successful personal test used live microphone recitation. Detailed sustained/format/interruption acceptance remains separate from that feedback.
- Continuation: owner approved measuring before setting performance targets and ten runtime recreation cycles. Offline five-minute measurement was prepared, but owner manually stopped after 125 seconds and chose to save that evidence rather than rerun. Mac/physical iPhone currently unavailable. Results and limits are recorded in `prototype/FEASIBILITY.md`; progress saved in local Git checkpoints.

### Next-session handoff

1. Inspect Git status/recent commits on master. This owner-requested5C/Android5D checkpoint follows73ba68e (5A/5B). Read section16/PHASE3/FEASIBILITY checkpoints before further work. Physical iPhone is deferred for now, not validated or removed from intended release support. No push, dry run or publication was performed.
2. Latest private APK targets lib/performance_probe.dart with PROBE_VALIDATION=switch-only (89.5MB), dev.qiyam.tilawa_bridge_probe, force-stopped after validation. Prior5D broader/resources modes use the same entry point;5C bridge/recovery probes remain separately runnable. Additional ignored private benchmark audio explains APK growth, not SDK archive size. Updated standalone example19.0MB remains installed, microphone/helper/session disposed, downloaded assets retained. SDK runtime artifact pins remain unchanged.
3. Phase4 diagnostic metadata mismatches17/resolverfailure were nonfatal; duplicate/revised progress and full transcripts replaced snapshots, lost remained diagnostic while sampled state tracking, scores above1 preserved, malformed operation batches suppressed and async mappings fenced across reset. Real runtime checked nine fixture ayahs/38 words. First113 replay5matches/48progress; second0newmatches/46newprogress; final113:1-5,112:1 yielded6matches/97progress/952012 samples and canonical result identity. Located3/completed2, no actual acoustic lost/relocated event in this run.
4. Owner confirmed Arabic words/ayah followed live recitation. Successful live stop5sequenceentries/485120samples, then reset cleared display and session/helper disposed. Earlier exploratory stops0/2 entries; no accuracy generalization. Labels come from pinned corpus; page604/juz30 fixture provenance/hash captured. Developer still verifies arbitrary real display data; SDK validates claimed identity/structure. No authored unit-test suite; root/probe analyze clean/release build passed.
5. Remaining gates: physical input-route changes/disconnection, renderer-process loss and native cleanup failure beyond controlled-adapter evidence; sustained resources/budgets/architecture decision, broader passages and Mac/iPhone. Phase5A/B example exists;5E–G final docs/licenses/package metadata/archive/consumer/dryrun remain pending. Publication/Qiyam integration remain separate requests.
6. Owner accepted the limited112/113 fixture.5A inventory in NOTICE and5B conventional example are implemented. Analyzer clean/19.0MB release APK installed as dev.tilawa.tilawa_flutter_example on Infinix X678B/Android14; empty-store download/progress/cancel/userretry/license/runtime passed. Reopened with airplane on/Wi-Fi/data off and no current network; owner confirmed live highlighting. Stop386560samples/4matches/48progress/final113:2–5 complete, not full-surah/accuracy proof. Reset cleared presentation/counts; session/helper disposed, connectivity restored. example/README holds reproducible setup/evidence. Physical iPhone/accessibility variants and broader/resource/fault gates remain open.
7. 2026-10-13 recovery evidence: real mic+stalled adapter initially left accepting/stopping after overload, despite400ms configured interruption budget. Fixed interruption-before-drain, bounded normal drain including partial chunk, discard-on-interruption/disposal and binding ownership until cleanup. Overload/stalledStop incomplete results,5 rapid Start/Stop cycles, helper replacement/dispose-duringStart/resetRestart, injected bridge loss/late output and failed/timed-out cleanup leases passed. Mid-response realHTTPS faults recovered in5requests; exhaustion2/cancel1 requests, no partial activation/stale stages, older version preserved. Real Android focus loss finalized completely/no autorestart/reset recovery; client/device mono16kPCM16 observed. Actual WebViewJS fault rejected pending feed/reset, fenced late output and fresh session completed. Normal113:1–5 replay5matches/49progress/388670samples/canonical result, silence/reset/disposal passed. Example denial/regrant, background interruption307200samples, reset/restart/stop288000samples and local reopen passed with ambient input, not new recognition accuracy evidence. Original grants/connectivity restored; see PHASE3/exampleREADME.
8. 2026-10-13 Android5D: pinned standalone1:2/2:255/36:1–5/59:22–24/114:1–6/114:3/3:23/113:1–5 and mid-ayah/noisy/silence cases yielded expected references.1:2 and114:3 were stop fallback/no liveprogress. Compound1:2repeat→113 omitted1:2; tracked2:255repeat→113 retained2:255 but omitted113:1–2. Complete finalization is not exhaustive recognition/history. Five-minute paced4.8million samples mean226.757ms/p95247/max352/354msmaxschedulelag;300.115s mic299.92sPCM mean221.834ms/p95240/max304, zeroerrors, sampled sessionhighwater7680samples. Fivecycles/open5.806..6.522s passed; renderer sample834MiB PSS duringrecreation then dropped, substantialswap duringmic. Runtime/budgets remain undecided. Raw ignored evidence under prototype/.cache/validation-evidence; full outcomes inFEASIBILITY. Phone connectivity0/1/1 unchanged, privateappforce-stopped/exampledisposed.

Reproducible assets/source are pinned in `prototype/baseline.json`; npm and Flutter lockfiles are saved. Downloaded source, model/corpus and generated runtime/build products are ignored by Git. The local release APK is at `prototype/app/build/app/outputs/flutter-apk/app-release.apk` and can be regenerated using the prototype README. Dedicated local repository/checkpoint commits were owner-authorized; no remote, push, publication or Qiyam integration occurred.

### Working permissions and boundaries

- Original handoff authorized planning only. On 2026-10-12 the owner additionally authorized Phase 1 setup and validation on the connected physical Android phone; this does not authorize later-phase execution or publication.
- Owner subsequently approved Phase 2 API design and then said proceed after the contract draft, authorizing Phase 3 implementation and its bounded integration checks. Deferred platform/resource gates remain; publication and later-phase execution require separate approval.
- Owner then requested commit of the Phase3 checkpoint and progression to Phase4. Commit88e77fe saved that checkpoint; Phase4 implementation/Android validation proceeded with the remaining Phase3 gates explicitly deferred.
- Owner accepted the limited display fixture, requested a detailed Phase5 plan, then requested saving that plan and committing current progress. This authorizes this local checkpoint, not automatic Phase5 execution, new tests, remote push or publication.
- Owner subsequently requested Phase5A+5B and explicitly authorized Flutter scaffold/dependencies/format/analyze/releasebuild and bounded physical-phone checks. This session implemented and validated those slices only; no new authored test suite, commit, push, dry run or publication.
- Owner then explicitly requested committing the5A+5B checkpoint locally. This does not authorize a push, later-slice execution, dry run or publication.
- On2026-10-13 owner requested proceeding with5C and authorized control/testing on the connected physical Android via scrcpy/ADB. iPhone is deferred for now. Bounded builds/diagnostics/device validation performed; no new unit-test suite, commit/push/publication action requested.
- Owner subsequently approved Android5D progression: broader passages, five-minute paced input plus five-minute foreground microphone, resource/recreation measurements. These device-specific measurements do not approve a memory budget, final architecture, intended-platform release or publication.
- Owner then requested committing the5C/Android5D progress locally for continuation in a new session. This authorizes the local checkpoint only, not push/publication or later-slice implementation.
- No Android emulator requested. iOS runtime verification is not available in the current Windows environment.
- Do not add or modify tests unless the owner explicitly requests them. Verification design remains necessary, but test authoring/execution needs permission.
- Owner authorized dedicated local repository and progress checkpoint commits during continuation. Push, remote repositories and pub.dev publication still require separate explicit authorization.
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
- 2026-10-12: Owner accepted current Android feasibility evidence for Phase 2 API design. iPhone and deferred Android/resource checks remain release gates; this is not full both-platform feasibility approval.
- 2026-10-12: Owner approved proceeding from the delivered API contract to Phase 3. Public development SDK implemented; first Android public-API replay passed online. Asset fault/recovery and new microphone-helper checks remain in Phase 3.
- 2026-10-12: Phase4 implementation/Android checkpoint verified; owner accepted limited112/113 display mapping without a full-Quran dataset request. Detailed Phase5 plan saved for another session, with current progress locally checkpointed at owner's request.

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

## 16. Detailed Phase 5 execution plan

**Saved:** 2026-10-12, at owner's request for continuation in another session.
**Status:**5A/5B complete;5C Android recovery and5D Android measurements checkpointed. Physical-route/renderer/native teardown, iPhone (deferred), recognition/resource/runtime acceptance and5E–G remain open. No publication candidate or dry run performed.
**Goal:** Turn the development SDK into a reproducible package another Flutter developer can install, understand and use, with verified Android/iOS behavior and accurate documentation.
**Finish:** A validated release candidate with satisfactory authorized pub.dev dry-run results. Actual publication remains separate.

### Starting baseline

- Phase3 checkpoint88e77fe, Phase4/plan45d4798 and5A/5B checkpoint73ba68e are committed. This owner-requested checkpoint follows73ba68e and saves5C recovery/Android5D evidence. Verify HEAD/status on resume.
- Current package:0.1.0-dev.1, publish_to:none, Dart^3.9.0 and Flutter>=3.35.1. Dependencies/runtime/upstream assets remain pinned; architecture remains provisional.
- Public example/ now exists and has Android evidence. Root LICENSE, CHANGELOG.md and .pubignore remain pending; prototype/ apps are private diagnostics.
- Recognition corpus covers114surahs; the accepted developer display fixture covers112/113 only. Broader recognition quality and full-Quran display mapping are different concerns; expanding that display dataset is not required.
- Android has real-device evidence. Mac/Xcode/physical-iPhone verification remains pending; earlier sessions had no Mac/iPhone available.
- Current root assets/runtime/manifest.json lists13,392,903 bytes (about13.4MB) of artifact payloads, excluding the manifest itself. Pinned downloadable model/corpus/I/O/license total74,733,380 bytes (about74.7MB). The77.1MB private probe APK and older86.1MiB Phase1 bundle are not publication-archive size measurements.

### Execution order and dependencies

5A -> 5B -> 5C -> 5D -> finalize5E -> 5F -> 5G.

Draft documentation alongside implementation. Start iPhone work once the required hardware is available. Windows can progress baseline/example/Android checks/docs/packaging, but final release readiness stays blocked by unverified intended-platform/resource gates. A runtime change requires revalidating affected example, documentation and packaging paths.

### 5A. Establish the release baseline

**Checkpoint (2026-10-12):** Baseline45d4798 on master, working tree clean before5A/5B. Exact artifact/distribution/license inventory is consolidated in NOTICE.md, including the public fixture as an NPL-1.2 derivative. Pins/integrity manifest remain unchanged. Package/version/publish_to and owner license/URLs/publisher/budget/runtime decisions remain open. Deferred gates are5C capture/native/bridge/cleanup/download faults,5D physical iPhone/broader passages/sustained resources/runtime acceptance,16KB-device runtime, and5E/F final terms/archive/consumer/dry run. No new commit or publication action is authorized by this checkpoint.

**Work:**
1. Review the saved Phase4/current-progress checkpoint and inspect branch/status; preserve any newer owner work. Establish the exact release baseline, creating additional commits only when requested.
2. Preserve the pinned upstream commit, model hashes, corpus/segmentation identity and runtime artifact integrity manifest.
3. Consolidate open gates from PHASE3/FEASIBILITY: capture/bridge faults, physical iPhone, sustained resources, broader recognition, final runtime and licensing decisions.
4. Inventory authored Dart/example code, bundled Tilawa implementation/derived constants, ONNX JS/WASM, recognition assets, example metadata and any proposed sample audio. Retain each item's origin, terms and distribution location.
5. Identify decisions needed before finalization: authored-wrapper license, real public repository/support URLs and eventual publisher, release version, and measured performance/resource targets. Do not invent URLs or silently select a publisher/license.

**Done when:** One clear baseline/open-gate inventory exists, provenance/license obligations are recorded, and the next example slice can be built without losing saved Phase4 evidence.

### 5B. Build the standalone developer example

**Checkpoint (2026-10-12):** Conventional example/ implemented using only public SDK barrels, with example-owned controller/UI, persistent downloaded assets, cancellation/retry/local-only reopen, explicit capture/control/recovery, guarded snapshot mappings and NPL-labeled9ayah/38word fixture. Android API24/iOS16 scaffold prepared, root SDK/runtime pins unchanged. Analyzer clean and arm64 release19.0MB built/installed. Fresh online download/progress/cancel/userretry/license dialog/runtime passed; explicitly network-disabled reopen and owner-confirmed live highlights passed. Complete stop386560samples/4verseevents/48progressevents/final113:2–5; reset cleared display/counts and session/helper disposal passed. Original connectivity restored. See example/README evidence table. iOS build/runtime and remaining5C/D release gates remain unverified; no archive/clean-candidate/dryrun claim.

**Deliverable:** Conventional example/ Flutter app consuming only exported SDK interfaces: package:tilawa_flutter/tilawa_flutter.dart and package:tilawa_flutter/microphone.dart. No lib/src imports, Qiyam types/services, private probe dependencies or Node/cache requirement.

Proposed structure:

```text
example/
  pubspec.yaml
  README.md
  lib/
    main.dart
    demo_controller.dart
    recitation_demo.dart
    metadata/
      demo_metadata_resolver.dart
  assets/
    small licensed metadata fixture
  android/
  ios/
```

**Workflows:**
- Asset setup: check availability, download missing assets, per-file progress, cancellation/retry, verified local reuse and meaningful errors. Use an app-owned persistent directory.
- Recognition: explicit microphone Start/Stop, discovered ayah references, current word-progress snapshots, final results, reset and disposal.
- Metadata demonstration: compatible Arabic word labels and page/juz references where supplied. Keep the accepted small112/113 fixture; identify its limited scope plainly. Other surahs still show references/indices and an honest unavailable-display-metadata state.
- Lifecycle: interruption/failure states and explicit recovery, without automatic capture/restart.
- Offline reuse: reopen the verified local installation with connectivity explicitly disabled.
- External PCM: document the public input seam and bounded producer requirements without making private fixture conversion an SDK capability.

**Choices/boundaries:**
- Download the large recognition assets by default instead of bundling them in the example APK. Runtime resources remain package assets.
- Controller/UI are example-owned; no particular application state-management framework becomes an SDK dependency.
- Replace progress/transcript snapshots; preserve run/ayah/request-generation guards around async metadata lookup.
- Label tracker evidence/scores honestly, with no certified correctness, repeat-credit or page-completion claims.
- Do not promote private benchmark audio until redistribution terms are established. Verify public-example fixture terms before redistribution; NPL obligations remain explicit.
- Keep Android API24+ and iOS16 configuration consistent with actual dependency/platform validation. Use scoped loopback configuration and microphone permission descriptions.

**Done when:** A developer following example instructions from a fresh checkout can download assets, recognize live input, stop/reset/dispose and reopen offline, without maintainer/private inputs.

### 5C. Close remaining Android failure-path gaps

**Checkpoint (2026-10-13):** Owner-authorized Android recovery work implemented/verified on Infinix X678B/Android14. Real capture overload exposed stalled drain blocking interruption; fixed and revalidated. Bounded capture drain, interruption/disposal, rapid controls/helper ownership, controlled bridge+cleanup leases, mid-response HTTPS retry/exhaustion/cancel, real Android focus loss and standalone example permission/background recovery passed. Actual WebView JavaScript bridge fault rejected pending feed, fenced late output and allowed a fresh session. Root/probe/example analyzers clean and arm64 release builds passed; normal native113:1–5 replay/stop/reset/silence/dispose passed. Physical headset routes/disconnection were unavailable; renderer-process death and native cleanup failure remain distinct unverified gates. See PHASE3.md and example/README.md. This partial5C checkpoint is included in the owner-requested local progress commit, not full release readiness. iPhone explicitly deferred for now.

Use existing private diagnostics for controlled faults and the standalone example for normal end-to-end behavior. No separate authored unit-test suite is assumed; test authoring remains a separate owner request.

**Capture:**
- Force producer-side queue overload while inference is slow; surface continuity loss rather than silently dropping audio.
- Interrupt while an accepted feed is stalled; verify cleanup/finalization deadlines and recovery.
- Rapid Start/Stop, repeated control calls, and helper attachment/replacement around resetting/disposal.
- Permission denial/regrant in the standalone example; background interruption and explicit foreground restart.

**Native audio:**
- Verify delivered client mono16kPCM16 before float conversion; keep requested/client/physical-hardware evidence distinct.
- Available audio-focus interruption, route changes and disconnections.
- Establish whether each recovery needs reset, a new helper or a new session; do not advertise unverified automatic recovery or hardware format.

**Runtime/assets:**
- Bridge disconnection/unexpected runtime failure, failed cleanup and disposal timeout.
- Late output after interruption/disposal; retained installation protection while cleanup is unknown/failed.
- Mid-response download interruption/retry, beyond prior injected initial-request retry.

**Done when:** Observed failures have predictable structured errors, explicit discontinuity/recovery behavior, and cleanup/lease documentation matching actual results. Fix demonstrated defects and revalidate affected paths.

### 5D. Verify iPhone, broader recognition and resource budgets

**Android checkpoint (2026-10-13):** Eight pinned benchmark clips/five derived cases completed in unlocked foreground; two mixed-passage cases retained as incomplete recognition outcomes. Five-minute paced input and300.115s real microphone capture finalized with equal processed/submitted samples, no capture errors and no sampled growing backlog. Five recreation/reset/disposal cycles passed. First session.open6.951s, subsequent5.806..6.522s; material renderer recreation sample853740KiB PSS and swap cost remain explicit acceptance items. Full evidence, timing/queue/memory limits and source-backed fallback caveat are in prototype/FEASIBILITY.md. Root runtime/model pins unchanged, private audio ignored/no public fixture expansion; analyzer clean/89.5MB arm64 private builds passed. iPhone deferred for now; final intended-platform/recognition/runtime/resource acceptance remains open. This is an Android evidence checkpoint, not completed5D or release clearance.

**A. Physical iPhone (requires Mac/Xcode/device):**
- Clean example build/sign/install, iOS16 deployment settings, WKWebView JS/WASM initialization and actual loopback/ATS behavior.
- Fresh download, local installation verification and fully offline initialization/recognition.
- Microphone permission/delivery/conversion/normal stop/disposal; background/audio interruption and available route recovery.
- Repeated session recreation. Prepared Podfile/Info.plist are starting configurations, not proof of iOS functionality.

**B. Broader recognition:**
- Use a small documented set of passages from beginning/middle/end of the Quran, short/longer ayahs, similar/repeated phrases, mid-ayah starts, passage changes, repetitions, silence and less-clear input.
- Record ground-truth/expected references, candidates/final sequences, progress and fallback behavior with fixture provenance. Keep private verification audio private unless its distribution terms are established.
- Do not infer a full-Quran accuracy percentage or correctness certification from a small functionality set. Broader recognition checks do not require a full-Quran display dataset.

**C. Resources and sustained behavior:**
- Separately measure asset verification/download, cold/warm initialization, processing relative to incoming audio, queue high-water/overruns, app/renderer memory (including transient peaks), and repeated reset/disposal/recreation.
- Measure sustained foreground capture and paced external input distinctly. Proposed initial duration:five minutes, extending only where results justify it; this is not an SDK duration limit and needs owner/device availability.
- Agree budgets from evidence. At minimum, sustained real-time operation must not accumulate an ever-growing queue. Do not label a renderer snapshot as a true peak or leak-free proof.

**Runtime decision:** Confirm WebView/WASM against both-platform evidence and agreed budgets. If it fails, pause release preparation for a bounded alternative-runtime checkpoint through the same adapter seam. Revalidate affected behavior after any change; do not quietly rewrite the public contract.

**Done when:** Both intended platforms have physical-device evidence and final runtime/resource acceptance is explicit. Without Mac/iPhone, progress other slices but keep release readiness blocked.

### 5E. Finalize public docs, licensing and package metadata

**Documentation:** README/public Dart comments cover Android/iOS setup/minimums, permissions/scoped loopback, downloaded/bundled/local files, external PCM/backpressure, event identity/order/snapshot semantics, stop/interrupt/reset/disposal, metadata validation/stale-result guards and error recovery. Supported-platform status and limitations must match observed evidence.

Keep distinctions explicit: corpus coverage versus measured recognition quality; recognition versus available display metadata; engine scores versus probabilities; tracker snapshots versus certified coverage; complete versus incomplete finalization. A developer should not need private PLAN/probes to use the released API.

**Licensing:** Choose authored-wrapper LICENSE after inventory, finalize NOTICE, preserve all third-party notices/asset exceptions, and establish public-example data/audio terms. Wrapper licensing does not remove NPL obligations for downloaded or compiled/bundled derived material. Do not describe the entire archive as MIT solely from upstream code licensing.

**Package metadata:** Final description/version, actual repository/support URLs, platform declarations consistent with verification, tested Dart/Flutter/dependency constraints, and CHANGELOG.md. Evaluate pins/compatible ranges based on tested behavior; no blanket dependency upgrade is implied.

**Done when:** API setup/guarantees/terms are understandable and correct, and package metadata references real decisions rather than placeholders.

### 5F. Verify the publication archive and clean consumer

**Archive:** Add .pubignore to exclude private prototypes/benchmark data, maintainer tooling/caches, build/local configuration, internal plans/checkpoints and large default recognition files. Retain public Dart code, runtime resources/integrity manifest, required licenses/notices, public docs and necessary example files.

.pubignore overrides .gitignore for publication in the same directory: reproduce necessary exclusions explicitly and audit the actual file list. Confirm no unintended data/credentials/development artifacts enter the candidate. Measure compressed/uncompressed archive sizes directly; probe APK size is not a substitute.

**Clean consumer:** Resolve candidate dependencies in a clean Flutter app/environment, load packaged runtime resources, download assets, recognize, then reopen offline. No private prototype directory, Node/npm or maintainer cache may be required. Verify inclusion of runtime licenses/integrity bytes, not merely development-checkout success.

**Authorized dry run:** Keep publish_to:none during development. Deliberately prepare the publication-candidate configuration once the dry run is authorized, then use dart pub publish --dry-run (or the equivalent Flutter CLI invocation). Inspect publication files, metadata/dependency validation, missing files and all warnings/errors. This step does not publish.

Current Dart guidance recommends less than100MB compressed and256MB uncompressed; check actual candidate and current guidance at execution. Reference:https://dart.dev/tools/pub/publishing (reviewed2026-10-12).

**Done when:** Correct archive/file list, clean-consumer operation and satisfactory dry-run findings are recorded. Publisher/account creation or actual upload is not assumed by a dry-run request.

### 5G. Final release-candidate handoff

Record candidate version/source revision, exact dependencies/runtime/assets, Android/iPhone devices/OS/tool versions, verification matrix, resource measurements/runtime decision, limitations, license inventory, archive/dry-run results and runnable example instructions.

Phase5 is complete only when:
- [ ] Standalone example works from fresh setup.
- [ ] Required physical Android/iPhone checks pass.
- [ ] Remaining capture/bridge release gates are resolved.
- [ ] Resource budgets and runtime choice are accepted.
- [ ] Docs/licenses/package metadata are complete.
- [ ] Candidate works without private development inputs.
- [ ] Authorized pub.dev dry run is satisfactory.

Actual publication is a separate requested action. Qiyam integration and correction remain outside this phase.

### Cold-session start

1. Read PLAN sections13/16 and the canonical Brain checkpoint; inspect Git status/log before editing.
2. Local73ba68e saves5A/5B; this owner-requested checkpoint saves5C/Android5D diagnostics/fixes/evidence. Read observed mixed-passage/resource limitations before further work. Resolve acceptance/deferred gates and obtain later-slice progression; no further publication/commit/push action is implied.
3. Recheck physical device/Mac availability; retain current deferred gates and the accepted limited display-fixture scope.
4. Save progress at completed slices and before long device work, distinguishing source changes from actual verification and blockers. Update this existing plan/Brain rather than creating duplicate task plans.
