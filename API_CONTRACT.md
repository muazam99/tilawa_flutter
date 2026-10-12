# Phase 2: Public Dart API contract

Date: 2026-10-12. Status: owner accepted this design basis and authorized Phase 3 implementation. The initial development SDK now lives under lib/; this document records the design contract, while README/PHASE3 distinguish implemented behaviour from verified outcomes.

Owner approved moving to API design after the Android feasibility checkpoint. Physical-iPhone verification and deferred Android acceptance checks remain release gates. WebView/WASM is provisional. This contract must work with either the current bridge or a later native adapter.

## 1. Scope and design decisions

- One public package, `tilawa_flutter`, Android and iOS 16+ intended targets. Platform support cannot be advertised as verified until its release gates pass.
- Recognition and tracking only. No correction, grading, application analytics, storage, UI or state-management dependency.
- Core input is externally supplied mono 16 kHz float32 PCM. Microphone capture is a separable convenience layer.
- A session owns one runtime and one recognition run at a time. Runtime sharing/pooling is not an initial guarantee.
- Typed immutable observations through a Dart broadcast stream. No WebView, JavaScript, ONNX tensor or Qiyam types in the ordinary API.
- `stop()` returns the same canonical result published by the session-ended event. Consumers choose one completion path for aggregation.
- An optional metadata resolver is independent of recognition and never delays the recognition stream.
- No automatic session duration limit. The prototype's five-minute timer is a measurement setting only.

Signatures below are the design basis. See exported Dart source for current constructors/signatures and PHASE3 for implementation limits; no release-readiness claim follows from approval.

## 2. Ordinary consumer API

```dart
// Signature sketch. Value-type members are specified in the tables below.
abstract interface class TilawaSession {
  static Future<TilawaSession> open({
    required TilawaPreparedAssets assets,
    TilawaRecognitionConfig config = const TilawaRecognitionConfig(),
    TilawaMetadataResolver? metadataResolver,
    TilawaEngineAdapterFactory? adapterFactory,
  });

  TilawaSessionInfo get info;
  TilawaSessionSnapshot get snapshot;
  Stream<TilawaEvent> get events;

  Future<TilawaFeedReceipt> feed(Float32List pcm);
  Future<TilawaSessionResult> stop();
  Future<TilawaSessionResult> interrupt(TilawaInterruption reason);
  Future<void> reset();
  Future<TilawaAyahMetadata?> resolveMetadata(TilawaAyahRef ayah);
  Future<void> dispose();
}
```

`open()` verifies prepared assets and compatibility, creates the selected adapter, and returns a ready session. Initialization failures throw a structured `TilawaException` and release partially acquired resources. There is no inaccessible initialization event stream before the returned object exists. Asset installation/loading progress belongs to the asset layer; a future opening-progress API may be added only if its semantics are reviewed.

`snapshot` is an immutable latest facade snapshot, not a synchronous call into the engine. It contains session ID, run ID, lifecycle state, current sampled tracking state, submitted/processed sample counts, last ordered event number and optional last canonical result. Reading it does not replay events.

### Value types

| Type | Required data / meaning |
|---|---|
| `TilawaAyahRef` | `surah`, `ayah`, both 1-based; value equality/hash. Validate against the active corpus rather than guessed ayah counts. |
| `TilawaWordRef` | Ayah reference plus 0-based `indexInAyah`, in the pinned recognition corpus's segmentation. |
| `TilawaSessionInfo` | Engine ID/version, upstream commit, asset manifest ID, corpus SHA-256, corpus segmentation ID, adapter ID/version, actual platform, capabilities and effective recognition config. No microphone/device identifiers. |
| `TilawaCapabilities` | Supported observation kinds, transcript representation, tracking-state availability, final-sequence support, correction=false, exact word timestamps=false. Describes adapter capability, not verified device performance. |
| `TilawaFeedReceipt` | Accepted input interval `[startSample, endSample)`, processed-through sample position when this operation completes. No recognition event list. |
| `TilawaSessionResult` | Session/run IDs, end reason (`stop` or `interruption`), finalization status (`complete` or `incomplete`), optional engine sequence, optional sequence score, latest transcript snapshot/representation, submitted/processed samples, immutable warning list. |
| `TilawaSequenceVerse` | Ayah reference and the upstream score. Sequence order is upstream first-seen tally order, not every reading occurrence. |
| `TilawaInterruption` | Stable reason code such as `background`, `audioFocusLoss`, `routeChanged`, `captureDisconnected`, `permissionRevoked`; optional non-sensitive details. |

All collections are defensive immutable copies, including nested diagnostic maps. Retaining an event/result cannot observe subsequent mutation. Caller-supplied objects are never modified by the SDK.

## 3. Lifecycle, control and concurrency

Lifecycle states: `ready`, `accepting`, `stopping`, `stopped`, `interrupting`, `interrupted`, `resetting`, `disposing`, `disposed`, `failed`. Tracking state (`searching`, `tracking`, `unknown`) is separate from lifecycle. `accepting` means an active input run, not microphone-on or speech-active.

| Operation / current state | Contract |
|---|---|
| First `feed()` in ready | Admits input, transitions to accepting. No separate `start()` needed. |
| `feed()` in accepting | Copies/validates admitted input and processes it in invocation order. |
| `stop()` in ready/accepting | Immediately closes input admission, drains accepted feeds, flushes once, publishes a canonical result, transitions to stopped. Empty input is a valid stopped run with an empty sequence if the engine successfully finalizes it. |
| Concurrent/repeated `stop()` | Share the same stop operation and canonical result. No second synthetic silence tail or final-sequence emission. |
| `feed()` after stop/interrupt/reset/dispose admission closure | Fails with `invalidState`; it is never silently appended to a closing or new run. |
| `reset()` in ready/accepting/stopped/interrupted | Closes admission immediately; waits for earlier accepted work, discards the run without implicit stop/finalization, resets decoder/tracker/inference caches, opens a new run in ready. |
| Concurrent/repeated `reset()` | Calls while the same reset is pending coalesce. A later reset after completion starts another run. |
| `stop()` during pending reset | Fails with invalidState. Caller awaits reset before starting/ending the new run. |
| `reset()` during pending stop/interrupt | Waits for that finalization, then clears the old run and becomes ready. Result/event retains its old run ID. |
| `interrupt()` in ready/accepting | Closes admission and attempts ordered drain/flush with a bounded interruption-finalization deadline. On unavailable runtime/deadline, fences/discards late output and publishes an incomplete result with `engineSequence=null`, not an invented empty sequence. |
| `interrupt()` during stop/interrupt | Does not launch another flush. First accepted terminal operation owns the result; subsequent calls await it. |
| `stop()` in interrupted | Returns that run's existing canonical result, including incomplete status. `reset()` is required to accept more audio. |
| `interrupt()` in stopped | Returns the completed result; does not change its recorded end reason. |
| `dispose()` in any non-disposed state | Closes admission immediately. Cancels capture if SDK-owned, waits for already accepted control/work where feasible within the disposal deadline, releases runtime/transport resources, closes events. It does not implicitly call stop or manufacture a final result. |
| Repeated/concurrent `dispose()` | Await the same cleanup operation; idempotent. |
| Any operation after disposed | Fails with disposed except repeated dispose and reading the final snapshot/info. |
| Engine/transport fatal error | State becomes failed, pending work fails, admission closes. Dispose is allowed. Recovery requires a new session; reset is not advertised as rebuilding a failed runtime. |

Facade serializes accepted engine operations, including metadata word-count queries that require an adapter call. Async callers cannot run inference/reset/flush concurrently. Admission checks happen at invocation before the first asynchronous yield. Already accepted PCM is copied before returning control to its caller.

Control operations are not queued as audio and cannot be rejected merely because the PCM buffer is full. New audio during a pending reset is rejected rather than implicitly assigned to the next run. The control arbiter preserves invocation order; reset/dispose are generation barriers. Calls queued behind disposal fail with disposed. Interrupt during resetting fails with invalidState; dispose during a control operation takes priority for closing admission and invalidates remaining work at its deadline.

Reset retains verified assets, runtime resources, immutable config, capabilities and metadata resolver. It clears transcript, tallies, suppression history, candidate/progress state, sequence results and sample counters. A new run ID is assigned; session ID and session-wide event sequence remain unchanged. No configuration mutation method initially: open a new session for different recognition settings. Correction's expected-passage retention is outside this contract.

Deadlines bound the caller's wait, not a promise that native/WASM execution is preemptible. A timed-out runtime is quarantined, cannot receive further input or be reset for reuse, and its output is ignored. Cleanup failure is reported explicitly. Actual cancellation/renderer teardown behaviour must be established per adapter in Phase 3 and platform validation.

## 4. Audio contract and backpressure

- `Float32List`, mono, exactly 16,000 samples per second, finite normalized values in `[-1.0, 1.0]`. Reject NaN/infinity/out-of-range input; no hidden normalization/clipping.
- Chunk size is arbitrary within the configured maximum. Zero-length input is rejected as invalidAudio. The initial proposed maximum is one second (16,000 samples); 480 ms is recommended for the pinned Zipformer adapter.
- Raw input must already be channel-converted/resampled. The SDK does not infer a recording format from a typed array.
- `feed()` makes a defensive copy at admission; caller may reuse/mutate its original buffer after invocation returns. A feed Future completes after its PCM has been consumed by the engine operation, not merely enqueued, and observations have been added to the stream. Some acoustic context remains buffered inside the engine until future input/stop.
- Proposed default outstanding PCM capacity: two seconds (32,000 samples), including the in-flight operation and all pending copies. Count samples/bytes, not just number of chunks. Per-chunk max must fit the capacity. These are bounded buffering defaults, not measured latency targets.
- Admission validates available capacity before copying/queueing. Over-capacity feed is rejected immediately through its Future with audioOverrun; none of that chunk is accepted. Prior accepted input continues. Consumers must report a discontinuity and stop/reset or explicitly supply the omitted data later in order. The SDK never silently drops or splices it.
- Awaiting feed serially is the recommended external-input path. A real-time capture callback needs a bounded producer; awaiting inside an async stream callback alone is not backpressure.
- No wall-clock recording-duration or speech-activity counter in the recognition API. Input duration is sample count / 16,000. Stop's synthetic silence is excluded from external input positions/duration.
- Buffer limits bound SDK PCM copies, not native engine caches or consumer stream subscriptions. Dart broadcast subscriptions paused by a consumer can buffer events; the consumer owns pause/cancel behaviour. No recognition coalescing or silent event dropping is promised to solve a slow subscriber.

`TilawaRecognitionConfig` initially exposes only source-reviewed Zipformer options: `minWordFraction` (default 0.5, valid `(0,1]`), `enableFallback` (true), `fallbackMaxDistance` (0.5, `[0,1]`), `stayOnSurah` (false), `tailDuration` (2 s, proposed valid `[0,5 s]`), `diagnostics` (false), `maxChunkDuration` (1 s), `maxOutstandingAudioDuration` (2 s), interruption/disposal deadlines (proposed 10 s each). Durations must map to whole samples where applicable. Validate rather than silently clamp. Reject unsupported adapter options before creating a run.

`allowGaps=false`, structural correction=false and slip head=false are fixed for the first release. Arbitrary engine knobs, legacy text-engine StreamingConfig presets and expected passages are not exposed. The recitation ZipformerSession uses EngineConfig, not the older StreamingConfig presets in core/types.ts; importing those presets would imply unsupported semantics.

## 5. Observations and identity

Each `TilawaEvent` carries immutable `TilawaEventContext`:

| Field | Origin |
|---|---|
| `sessionId` | Opaque identifier for the opened runtime/facade. |
| `runId` | Opaque identifier for one reset-delimited recognition run. |
| `sequence` | Strictly increasing session-wide integer, starting at 1; includes lifecycle, observation, warning and completion events. |
| `emittedAt` | Facade UTC wall-clock timestamp. Clock adjustments can make it non-monotonic. |
| `elapsedSinceOpen` | Facade monotonic duration; includes initialization only if its origin is explicitly recorded in info. Proposed origin: successful open. |
| `inputPositionSamples` | Successfully processed-through externally supplied sample position at operation level, or null if unavailable. Not a decoded word's acoustic timestamp. |

Upstream callbacks occur inside feed before the operation completes. Buffer their immutable observations per operation, then attach that operation's completed input position and emit them in upstream order. This creates chunk-level positions, not token timestamps. If an operation fails, suppress its uncommitted observation batch, mark session failed and report processing position as last successfully completed operation. Stop-tail observations use the final external position.

### Recognition events

| Event | Payload and meaning |
|---|---|
| `TilawaStateChanged` | Previous/current lifecycle states and optional reason. No claim that every internal engine transition is observed. |
| `TilawaTrackingStateObserved` | Latest sampled searching/tracking/unknown state after an operation. May miss transitions inside a chunk. A lost diagnostic can occur while state remains tracking. |
| `TilawaVerseCandidates` | Immutable candidates (`ayah`, optional inclusive `ayahEnd`, score, rank, source), stable and finalFlush flags. Preserve source/rank/order, including rank=0. |
| `TilawaVerseMatched` | Ayah, upstream score, optional engine-supplied text/name/context. Empty engine display strings become absent values. Match provenance is `notProvided` unless an adapter has explicit reliable evidence; do not infer tracker/fallback origin from confidence or ordering. |
| `TilawaWordProgress` | Ayah, 0-based wordIndex, totalWords and matchedIndices. Snapshot of current tracker verdicts; can repeat/revise/shrink/jump. Both ok and unsure are included. |
| `TilawaTranscriptUpdated` | Full cumulative text since reset, representation=`phonemes` for Zipformer, upstream score. Snapshot replacement, not append delta. Live score=1 may be a placeholder, not measured certainty. |
| `TilawaFinalSequenceObserved` | Engine's sequence and score, emitted once on a successful stop/interrupt flush. Retains its position before the trailing final transcript in upstream order. Not a second canonical completion notification. |
| `TilawaDiagnostic` | Opt-in upstream name, source timestamp (separate from facade emission time) and immutable payload. Version-sensitive and possibly contains recitation data. Not ordinary analytics inputs. |
| `TilawaWarning` | Structured nonfatal problem such as metadata mismatch or incomplete interruption finalization; operation ID when relevant. |
| `TilawaFailure` | Structured fatal error, operation ID and last valid snapshot. Event stream uses typed failure events rather than Stream.addError for engine failures. |
| `TilawaSessionEnded` | Canonical TilawaSessionResult. stop/interrupt Future returns this same immutable result object after all preceding observation/state events have been enqueued. |
| `TilawaUnknownObservation` | Original upstream kind and immutable unrecognized payload. Forward compatibility, not a supported semantic capability. |

Success ordering: close admission and emit stopping/interrupting state, accepted-feed observations, upstream flush observations (final sequence followed by final transcript at the pinned baseline), stopped/interrupted state, session-ended event, then complete the terminal Future. Completion means events are added, not that every async subscriber callback has finished. Failure emits failed state then failure; the failed operation Future throws the same structured error. Disposing emits disposing/disposed state before closing the stream, without session-ended unless stop/interrupt already owns a result.

Consumers should switch with a default branch for future typed event kinds. No public JSON serialization contract in the initial API. Diagnostic/unknown payloads are not stable serialized API schemas; a future serialization format requires independent schema/version review.

Broadcast streams are non-replaying. No subscriber is required to run recognition; late subscribers miss earlier events and should read snapshot. Canceling a subscription does not stop/dispose recognition. Listener exceptions are consumer errors, not engine failures. Old-generation output after reset/disposal is fenced before entering the stream. Result Futures retain old run identity even if a reset follows.

## 6. What the pinned upstream actually establishes

Baseline: `2f2617460dc4a6b967e0cc49fa04804bbf22ec69`, core metadata 0.4.0, assets in prototype/baseline.json.

| Topic | Source observation and contract consequence |
|---|---|
| Matching gate | emission.ts:52..64 computes `(ok + unsure) / words`; gate also requires `wrong <= ok + unsure`. Default minWordFraction=0.5. An emitted verse is not all words read or correctness certification. |
| Word snapshot | emission.ts:211..239 filters verdicts to the cursor's ayah and states ok/unsure, uses ayah-local `word`, sorts indices. Cursor does not certify intervening words. Preserve repeated/revised snapshots; do not manufacture increments. |
| Candidate quality | session.ts:919..935 emits one discovery candidate on located with confidence=0.5, rank=0, stable=false, final_flush=false. This candidate is not a calibrated ranked probability distribution. |
| Duplicate suppression | session.ts:284..285/1035..1044 stores ayah keys in emitted until reset. Re-reading a matched ayah need not emit another verse_match. |
| Accumulated tally limits | emission.ts:95..112 adds snapshots by ayah key and keeps firstSeen. Counts can exceed word count and confidence can exceed 1. Preserve finite upstream scores without clamping or probability language. Tallies are not unique word coverage or repeat-credit counters. |
| Final sequence | emission.ts:181..208 filters tallies by gate and orders firstSeen. It does not enumerate every reading occurrence. Gap filling affects the optional verses getter, not automatically this final-sequence builder. First release disables gaps. |
| Fallback caveat | session.ts:574..604,612..622 searches only if no verse emitted, inserts an all-ok tally for a fallback hit, then builds final sequence from that tally. Verse/final scores can be 1 despite search distance; fallbackConfidence is not necessarily the delivered score on this path. Fallback match does not establish actual per-word verdict coverage. |
| Transcript | session.ts:738/760..765 accumulates phoneme token symbols, live confidence=1. stop emits full transcript again with sequence score. No ordinary Arabic transcription claim. |
| Lost / relocation | session.ts:908..959 does not publish ordinary lost/relocated messages; these are debug when enabled. Lost can retain tracker position, while idle/completed restarts search/decoder. No fabricated always-complete tracking-transition stream. |
| Stop | session.ts:539..623 adds default two seconds of silence, finishes fbank/decoder, settles matches/fallback, emits final sequence and trailing transcript. Facade makes this terminal/idempotent because upstream itself does not impose that lifecycle. |
| Reset | session.ts:454..469/650..657 clears recognition/acoustic caches and recreates search engine while retaining runtime/model/corpus. It returns no events; facade state events are SDK-generated. |
| Event ownership | session.ts:675..682 both invokes onEvent and returns the same message list. Adapter uses onEvent as the sole observation ingestion path and must not emit returned arrays a second time. |
| Disposal | Upstream session has no public runtime-dispose contract here. Adapter must release the owned inference runtime and transport independently, as the prototype explicitly does. |

Source links: [session.ts](https://github.com/yazinsai/tilawa/blob/2f2617460dc4a6b967e0cc49fa04804bbf22ec69/packages/core/src/recitation/session.ts), [emission.ts](https://github.com/yazinsai/tilawa/blob/2f2617460dc4a6b967e0cc49fa04804bbf22ec69/packages/core/src/recitation/emission.ts), [public messages](https://github.com/yazinsai/tilawa/blob/2f2617460dc4a6b967e0cc49fa04804bbf22ec69/packages/core/src/types.ts), [engine types](https://github.com/yazinsai/tilawa/blob/2f2617460dc4a6b967e0cc49fa04804bbf22ec69/packages/core/src/recitation/types.ts).

## 7. Metadata extension

```dart
abstract interface class TilawaMetadataResolver {
  TilawaMetadataDescriptor get descriptor;
  Future<TilawaAyahMetadata?> resolveAyah(TilawaAyahRef ayah);
}
```

Descriptor identifies metadata version, Quran edition/layout, recognition corpus SHA-256 and segmentation ID. No default universal page layout. For this baseline, corpus SHA-256 is `24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127`. The adapter must publish a stable segmentation ID tied to this corpus before Phase 3; do not invent a compatible text edition.

Ayah metadata contains the requested ayah, optional display text and immutable mapping rows for recognition word indices. Each row can map to one or several display-word IDs/positions and page/juz references. Pages/juz are edition-specific references, not read counters. Explicit optional ayah-level page/juz references are separate from word mappings and cannot imply word-level precision.

`resolveMetadata()` runs separately from feed/event delivery. Validate descriptor compatibility, returned ayah, recognition word count, index bounds and complete/exactly-once recognition-index mapping against adapter corpus description. Display segmentation can be one-to-many or many-to-one if rows explicitly state it. Missing word mappings fail word-level validation; an explicitly ayah-only mapping can still provide display text/ayah pages without word highlights. Bismillah/end markers are display-only unless the corpus explicitly includes them. Never compare list length including display decorations to recognition word count.

No resolver or resolver returns null: return null without breaking recognition. Descriptor/index/count mismatch: throw metadataMismatch and emit a nonfatal warning; return no invalid highlight mapping. Resolver exception: metadataResolutionFailed, nonfatal. Returned metadata identifies its ayah/descriptor but does not carry session state; a consumer captures run ID before awaiting it and checks that ID before updating live UI. A result completing after reset is not automatically attached to the new run. The SDK does not enrich/reorder recognition events asynchronously behind the consumer's back.

SDK retains a resolver reference but does not dispose a caller-owned resolver. Metadata changes require a new session/resolver binding; no ambiguous mid-run version switch.

## 8. Asset and adapter boundaries

### Assets

`TilawaPreparedAssets` describes a completed, integrity-checked local installation, not a URL/download promise. It includes versioned manifest, model/corpus/I/O file references and applicable notices. The initial manifest binds engine/upstream versions, corpus/segmentation identity, each file size/SHA-256, model I/O schema and license inventory.

Planned preparation entry point: `TilawaAssets.fromLocalFiles(manifest: ..., model: File(...), corpus: File(...), io: File(...)) -> Future<TilawaPreparedAssets>`. Applications can supply their own files. Bundled/downloaded preparation, progress, cancellation and atomic installation belong to Phase 3. They must converge on the same prepared-assets contract. No installation/network dependency from feed/stop after opening.

Session may revalidate files before opening; a prepared handle cannot make an altered file trusted forever. Default large assets stay outside the pub.dev archive. Deleting/replacing assets while a session holds them must be prevented or safely leased; interrupted replacement preserves the existing valid version. Caller owns prepared files; session disposal releases its lease/resources, not the installation itself.

### Advanced runtime adapter

Optional `adapterFactory` is a Dart-only advanced seam, separate from the ordinary consumer API. Proposed `TilawaEngineAdapterFactory.create(preparedAssets, recognitionOptions, observationSink)` returns an adapter with serialized `feed`, `stop`, `reset`, `describeAyah` and `dispose` operations plus capability/identity info. Engine observations use typed Dart payloads without facade identity/timestamps. Adapter operation snapshots contain engine state and consumed sample counts; stop snapshot includes final transcript/sequence evidence.

Factory-created adapters are transferred to SDK ownership: session always disposes them, including open failure. Externally owned ONNX sessions/runtime objects are not accepted by the high-level API initially. An advanced factory may manage borrowed infrastructure but must release its own lease and document that ownership internally.

One observation sink per adapter. Callbacks are non-reentrant, scoped to their producing operation, and fenceable by run/operation token. They do not call consumer code directly. Stop's snapshot and observation batch must agree; contradictions fail as invalidEngineOutput rather than synthesize data. Partial initialization/cleanup and unsupported options are structured errors. New engines must declare capability differences; alternate FastConformer/correction parity is not assumed.

The engine adapter is not a microphone adapter. A consuming app can feed its own recorder without implementing an inference seam.

## 9. Optional microphone convenience

Proposed separate import: `package:tilawa_flutter/microphone.dart`. Core event/session usage does not require the helper to capture or request permission.

`TilawaMicrophone.open(session: session)` returns an SDK-owned capture controller with `start()`, `stopCapture()`, `dispose()`, state stream and actual delivered-format information. `stopCapture()` stops the native source and drains its accepted producer buffer; it does not finalize the recognition session. Caller then invokes session.stop for the canonical result. Helper disposal cancels capture and releases recorder resources without disposing a caller-owned session.

Helper validates delivered format, converts/resamples supported formats to mono16kfloat32, carries incomplete PCM samples across callbacks and uses bounded producer buffering. It must not assume requested rate equals actual hardware rate. Producer capacity plus session capacity are separately documented; no unbounded async stream callbacks. Overrun stops capture and reports the discontinuity.

Foreground-only first-release policy. On interruption/route uncertainty, stop capture, notify capture state and call session.interrupt with explicit reason. No automatic capture or recognition resume; caller resets/restarts deliberately. Route conversion/recovery, permission denial/revocation and background behaviour still require platform evidence. A helper cannot promise successful flush while the platform suspends its runtime.

## 10. Errors and feature reporting

`TilawaException` wraps immutable `TilawaError` with category, stable code, message, operation ID, retry guidance and non-sensitive details. Proposed categories: invalidInput, invalidState, assets, compatibility, unsupported, runtime, audio, metadata, disposal.

Stable codes include invalidAudio, audioOverrun, invalidState, disposed, assetMissing, assetIntegrityMismatch, incompatibleAssets, unsupportedPlatform, unsupportedCapability, runtimeInitializationFailed, inferenceFailed, invalidEngineOutput, bridgeDisconnected, operationTimeout, metadataMismatch, metadataResolutionFailed and disposalFailed. Platform permission/capture failures belong to the microphone layer and preserve platform cause codes without leaking native objects.

- Invalid input/state and rejected overload: operation Future fails; session remains usable unless the consumer's audio continuity was broken. No fatal failure event.
- Metadata failure: Future fails plus nonfatal warning, no recognition interruption.
- Fatal engine error: failed lifecycle plus failure event and failed pending Futures.
- Incomplete interrupt finalization: explicit incomplete result/warning, engine sequence absent, reset only if runtime remains healthy; quarantined runtime requires new session.
- Unknown event kind: unknown observation, not fatal. Malformed known event: invalidEngineOutput. Validate indices/counts, required fields and finite scores without pretending scores must be <=1.
- Unsupported capability/config/platform: explicit failure, never an ignored option or fabricated result.

## 11. Consumer examples (proposed API, not executable yet)

### Externally captured audio and typed observations

```dart
Future<TilawaSessionResult> recognize(
  TilawaPreparedAssets assets,
  Stream<Float32List> orderedMono16kPcm,
  void Function(TilawaEvent) onObservation,
) async {
  final session = await TilawaSession.open(assets: assets);
  final subscription = session.events.listen(onObservation);
  try {
    // The producer must already be bounded and supply the documented format.
    await for (final chunk in orderedMono16kPcm) {
      await session.feed(chunk);
    }
    // This consumer chooses the Future as its one completion/analytics path.
    // onObservation must not also persist TilawaSessionEnded as a second result.
    return await session.stop();
  } finally {
    await session.dispose();
    await subscription.cancel();
  }
}

void onObservation(TilawaEvent event) {
  switch (event) {
    case TilawaWordProgress():
      // Replace that ayah's current snapshot. Do not count every message
      // or every cursor advancement as newly recited words.
      renderProgress(event.ayah, event.wordIndex, event.matchedIndices);
    case TilawaTranscriptUpdated():
      renderTranscript(event.text, event.representation);
    case TilawaFailure():
      showRecognitionFailure(event.error);
    default:
      // Handle other desired observations; tolerate future event variants.
      break;
  }
}
```

`renderProgress`, `renderTranscript` and `showRecognitionFailure` are application callbacks, not SDK functions. The sample does not implement microphone capture, page completion or persistence.

### Optional metadata

```dart
final session = await TilawaSession.open(
  assets: preparedAssets,
  metadataResolver: myEditionResolver,
);
final runId = session.snapshot.runId;
final mapping = await session.resolveMetadata(progress.ayah);
if (session.snapshot.runId == runId && mapping != null) {
  // Pass recognition indices through the validated mapping before highlighting.
  // A mapped page reference does not mean that the whole page was read.
  renderMappedProgress(mapping, progress.matchedIndices);
}
```

The consumer also checks whether the latest live cursor still refers to this ayah before replacing its UI. Metadata errors should be handled as optional display failures, not as recognition correctness failures.

## 12. Review and Phase 3 handoff

Owner approved progression to Phase 3 after this draft was delivered. Phase 2's design checkpoint is accepted; implementation limits/defaults and platform results continue to be recorded explicitly.

Accepted design direction:

1. Accept core `feed`, terminal `stop`, explicit `reset`, interruption and disposal methods, with one canonical completion result.
2. Accept snapshots and uncalibrated engine scores, including unsure-matched indices and duplicate suppression; no repeat/coverage claims.
3. Accept separate microphone and metadata layers, provisional buffer/deadline defaults and factory-owned runtime adapters.

Phase 3 must implement/verify cancellation and control arbitration, immutable event validation, audio conversion/bounded queues, local/bundled/downloaded asset installation, runtime cleanup and optional metadata validation queries. Resolve the corpus segmentation ID and adapter schema before implementation. No API/runtime performance promise follows from this document.

Outstanding release gates remain tracked in PLAN/FEASIBILITY: physical iPhone, longer capture, denial/interruption/route recovery, agreed startup/latency/memory budgets, 16 KB-page runtime and architecture/resource review. Correction, Qiyam integration, package licensing/publisher and publication remain separately scoped.
