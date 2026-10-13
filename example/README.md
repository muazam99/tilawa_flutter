# Tilawa developer example

Standalone Flutter app using only `package:tilawa_flutter/tilawa_flutter.dart` and `package:tilawa_flutter/microphone.dart`. No Qiyam service, private probe, Node/npm or maintainer model cache is required. This is a development example, not an official upstream app or a published release.

## Setup

Use Flutter3.35.1 / Dart3.9 or compatible. From this `example` directory:

```sh
flutter pub get
```

Connect a physical Android phone, select its ID from `flutter devices`, then:

```sh
flutter run --release -d <device-id>
```

Android requires API24+. The checked-in manifest contains INTERNET and RECORD_AUDIO permissions. Cleartext HTTP is allowed only for127.0.0.1/localhost, for the SDK's app-owned local runtime server. Asset downloads use HTTPS. Release builds use the generated debug signing key for local demonstration, not store distribution. Kotlin incremental compilation is disabled to avoid the Windows cross-drive cache failure observed during earlier validation.

For iOS, use a Mac with Xcode/CocoaPods and a physical iPhone. The Podfile, Xcode project and AppFrameworkInfo target iOS16; Info.plist contains a microphone description and NSAllowsLocalNetworking. Select your development signing team in Xcode, then run the same Flutter command with the iPhone ID. **iOS build/runtime is still unverified.** The prepared configuration is not both-platform validation evidence.

## Workflows

1. Launch performs a **local-only integrity check**. It does not download or start the microphone. A missing installation leaves recognition controls disabled.
2. Read the asset license, then tap **Download / retry** while online. Model/corpus/I/O/license total74,733,380 bytes (about74.7 MB). Per-file progress includes received/expected bytes and attempt. **Cancel download** aborts the active installer and waits for staging cleanup. Retry starts again rather than resuming an HTTP range. The installer permits two retries per file.
3. Verified files live in the app's persistent application-support directory under `tilawa-assets`. Interrupted process staging is cleaned before store setup; complete versions are retained. Opening a runtime performs integrity verification again.
4. Tap **Start microphone**, grant microphone permission and recite. Input stays on-device. No recording is stored or uploaded. Start is always explicit; keep the app foregrounded.
5. Observe discovered references, candidates, sampled tracking and current word snapshots. Display labels/page/juz exist only for surahs112/113. Other recognized ayahs retain references/indices with an unavailable-display message.
6. Tap **Stop** to drain capture and finalize the run. Finalization complete/incomplete, submitted/processed samples and the final engine sequence are shown. The controller consumes `TilawaSessionEnded` as its single result path; it does not count the returned stop result again.
7. **Reset** stops/disposes the old microphone helper, clears run presentation and resets a healthy runtime. Tap Start explicitly to attach a new helper. After permission denial, correct OS permission settings and retry Start. After background/audio interruption, wait for finalization, then Reset. A failed/quarantined runtime requires Dispose and Reopen rather than Reset.
8. **Dispose session** releases runtime and its attached helper without implicit finalization; stop first if you want a final result. Verified asset files remain. **Check / reopen local** opens them again without a network fallback. Widget teardown also cancels setup and releases acquired resources.
9. To establish offline reuse, dispose, explicitly disable external connectivity (airplane mode plus Wi-Fi off), then reopen local and recite. No network status is inferred from a local-files message. Restore the phone's original connectivity afterwards.

Errors display SDK code/message and recovery guidance. No automatic microphone restart occurs. Cleanup failure blocks further setup in this controller: restart the app, and do not remove files while cleanup/leases are unknown. If a local installation fails integrity verification, dispose any session and clear this example's application storage through OS settings before a fresh download. Clearing storage removes the downloaded installation; ordinary disposal does not.

## Metadata, evidence and analytics

`assets/demo_metadata.json` is an **NPL-1.2 derivative** of the pinned corpus's unmodified `w[2]` word labels:9 ayahs/38 recognition words in112/113. Its descriptor binds the exact corpus SHA-256 and segmentation. Example-owned Madani page604/juz30 annotations were checked against the Phase4 fixture; no private layout dataset is copied or needed. The full NPL text accompanies this fixture in the dependency's `assets/runtime/NPL-1.2.txt` and is available through **Read full asset license**. Retain it with any redistribution and do not add different terms to the derivative. See the root NOTICE inventory for upstream MIT/ORT exceptions and the still-undecided authored-wrapper/example license.

The SDK validates declared compatibility and mapping structure, not the correctness of arbitrary display text/layout. This resolver is not a default Quran edition or a full-Quran display source. Corpus coverage of114surahs is not an accuracy percentage.

Progress and transcript events replace current snapshots, including revisions and repeats. Async mappings are guarded by session identity, run ID, ayah and request generation; resetting, changing ayah or disposing invalidates old lookups. No private presentation class is imported.

Tint shows tracker ok/unsure evidence; the border shows the0-based cursor. Accessibility descriptions identify both without relying only on color. Neither means certified correct recitation, all preceding words read or ayah completion. Candidate/final scores are uncalibrated engine values and may exceed1. Phoneme transcripts are not ordinary Arabic text. Final engine sequences suppress some repeats, so they are not a complete reading history.

The only example-owned aggregation is **event counts for the current run**, reset with run state. Those counts illustrate where consumers can handle observations, not reading minutes, repeat credit, page completion or persisted analytics. Page/juz numbers are layout references only.

## External PCM seam

Applications can omit the microphone helper and use the same public session:

```dart
// Import dart:typed_data and package:tilawa_flutter/tilawa_flutter.dart.
// session and mono16kChunks are owned by your application.
await for (final Float32List chunk in mono16kChunks) {
  await session.feed(chunk);
}
await session.stop(); // Consume either its result OR SessionEnded, not both.
```

Supply mono16kHz float32 PCM in[-1,1]. Decode/resample external files in your application; the SDK feed seam does not decode WAV or infer raw PCM rate. Each chunk defaults to at most1second, and outstanding session audio is bounded to2seconds. Await feeds in order **and bound your producer queue**; an unbounded upstream stream buffer or asynchronous listen callback defeats backpressure. An audioOverrun is a continuity failure, not permission to silently drop/retry the rejected audio as though input remained continuous. The optional microphone helper supplies its own bounded queue and explicit interruption behavior. No private benchmark audio or conversion code is packaged here.

## Verification checkpoint

2026-10-12: Flutter 3.35.1 / Dart 3.9, analyzer clean, arm64 release APK built (19.0 MB) and installed as `dev.tilawa.tilawa_flutter_example` on physical Infinix X678B / Android 14. This app's own persistent store started empty, separate from the private probes.

| Check | Observed outcome |
|---|---|
| Fresh setup | Missing-assets state, disabled capture, HTTPS progress, verified download and runtime ready. |
| Cancel / retry | Cancelled an active fresh download after resetting this disposable example's data; explicit cancellation state, then successful fresh download and runtime ready. This is user retry, not a new injected automatic-retry fault check. |
| Retained license | Full NPL-1.2 dialog opened from the dependency's packaged runtime asset. |
| Dispose / local reopen | Session disposed, retained installation reopened with microphone idle. |
| Explicitly offline | Airplane on, Wi-Fi/data off; dumpsys reported no active default network and no current networks. Local runtime reopened successfully. |
| Offline live capture | Owner tapped Start, granted permission, recited and tapped Stop; confirmed live Arabic highlighting worked. Observed tracked113:5, page604/juz30, cursor4 and indices[0,1,2,3,4]. |
| Final result | Complete stop,386,560 processed/submitted samples,4 verse-match events/48 progress events; final sequence113:2–5. No claim that an entire recited surah was recognized. |
| Reset / helper disposal | Ready/idle, cleared ayah/progress/metadata/result/transcript and zero counts; then session not open/helper disposed. |
| Device restoration | Airplane off, Wi-Fi/data on, matching original settings; microphone stopped and session disposed. |

This is bounded functionality evidence, not an accuracy, sustained-resource or leak-free assessment. Physical iPhone, remaining route/renderer/native cleanup faults and resource budgets remain release gates. Dark-mode/large-text/landscape accessibility runtime coverage is still pending. Package archive size and publication dry run belong to later slices, not this APK measurement.

### Android recovery continuation (2026-10-13)

Updated SDK helper, analyzer clean and19.0MB arm64 release APK installed on the same phone. Verified existing installation/runtime opened without a new download. Deliberate OS microphone denial returned microphonePermissionDenied, session ready/helper failed, with explicit retry available. Restoring the original grant allowed the same example to Start successfully.

Leaving for Home during capture stopped the recorder, completed a background interruption with307200processed/submitted samples and left session/helper interrupted when foregrounded. No automatic restart. Explicit Reset/new-helper Start then Stop completed with288000processed/submitted samples; empty ambient-input sequences are lifecycle evidence, not recognition accuracy. Dispose retained files; local reopen returned ready/idle and cleared run presentation. Final helper/session disposed, original granted/USER_SET permission flags restored; airplane0/Wi-Fi1/data1 unchanged.

Separate private diagnostics validated capture overload/stalled shutdown, rapid controls, real Android audio-focus loss, actual WebView JavaScript bridge error and mid-response HTTPS recovery. See root PHASE3.md for fault mechanisms and limits. Physical headset routes/disconnection, renderer-process loss/native teardown failure remain open; iPhone deferred for now.
