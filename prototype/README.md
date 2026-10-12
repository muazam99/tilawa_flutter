# Tilawa Flutter: Phase 1 probe

A private Android/iOS probe for the pinned upstream Zipformer pipeline. Phase 0 is complete. Phase 1 has Android recognition evidence but remains incomplete until the outstanding gates in [FEASIBILITY.md](FEASIBILITY.md) are addressed.

## Setup

Requirements: Node.js 22+, Flutter 3.35.1 / Dart 3.9 or compatible, Android SDK for Android, Mac/Xcode/CocoaPods and an iPhone for iOS. The prototype targets Android API 24+ and iOS 16+. Windows cannot validate the iOS build.

From `tilawa_flutter/prototype`, install the locked tooling with `npm ci --ignore-scripts`, then run `npm run prepare:runtime`. Setup downloads and verifies the pinned source, model, corpus, I/O manifest, notices and two sample clips, then generates a local JS/WASM bundle.

From `tilawa_flutter/prototype/app`, run `flutter pub get`, then `flutter devices` and `flutter run --release -d <device-id>`. Use a physical device and keep the app foregrounded.

For automatic replay/lifecycle probes: `flutter run --release -d <device-id> --dart-define=PROBE_AUTORUN=true`.

For the bounded threaded-WASM experiment: append `--dart-define=PROBE_THREADS=4`. The runtime uses one thread if the WebView lacks actual cross-origin isolation or SharedArrayBuffer. The inspected Android WebView did lack these capabilities, even with COOP/COEP headers.

For the continuation measurement build, append `--dart-define=PROBE_CYCLES=10 --dart-define=PROBE_MIC_SECONDS=300`. Run probes repeats release/initialize/single-ayah recognition for ten extra cycles (allowed range 0..10). Start mic remains manual; the optional deadline stops it after five minutes. Android snapshots distinguish client PCM format from device-side capture format and include app PSS only, not renderer memory. Mic diagnostics record byte counts, feed timings, queue high-water, overruns and observation counts without recited references/transcripts. Sample renderer memory separately through ADB.

## Controls

- **Single ayah:** replay pinned upstream `ref_112001`, expect 112:1.
- **Multi ayah:** replay pinned upstream `multi_113_001_005`, expect 113:1-5.
- **Run probes:** single/multi replay, silence, real-time-paced replay, explicit runtime release/recreation and repeated single-ayah replay. Replay checks require expected final sequences and nonzero word progress; no accuracy generalization is implied.
- **Start mic / Stop mic:** optional native PCM16 capture and Flutter-to-JS feed path. Grant microphone permission, recite, then stop. Requested capture format is mono 16 kHz; delivered hardware format, sustained latency, real recitation and interruptions require separate validation. Microphone transcripts/payloads are not printed to the device log.

Observations are raw upstream events with private probe metadata. Word indices are 0-based. Empty display text is intentional: this phase has no display Quran metadata. Phoneme transcripts are not ordinary Arabic text. Duplicate word-progress observations are preserved.

The Android probe holds its own window awake while foregrounded. It does not change system sleep settings. Leaving the foreground stops microphone capture; full interruption/route-change behaviour is not yet established.

## Local runtime and licensing

The app uses an app-owned loopback HTTP server, bundled JS/WASM, and local model/corpus files. No PC server, hosted Tilawa page, CDN script or audio upload is used at recognition time. Android fresh/warm initialization, sample replay and a 125-second live microphone pass succeeded with airplane mode on and Wi-Fi disabled. iPhone offline verification remains outstanding.

Model bundling is for this feasibility probe only. Generated runtime files and downloaded source/models are Git-ignored; they are not the intended public-package archive.

- Upstream code: MIT with the asset exceptions described in the pinned NOTICE.
- Default model/corpus/vocabulary-derived material: NPL-1.2. Keep its license with distribution; powered features cannot be charged for.
- ORT: MIT plus retained third-party notices.
- Benchmark clips: local verification only until provenance/redistribution terms are reviewed.
- Authored wrapper license remains undecided; this app has `publish_to: none`.

Android release builds currently use Flutter's generated debug signing key for local installation. The 73.8 MB arm64 APK is a probe artifact, not a store/public SDK release.

## Evidence

See [FEASIBILITY.md](FEASIBILITY.md), including continuation evidence and remaining gates. Device logs have the prefix `TILAWA_PROBE`. Five-minute automatic stop is a configurable measurement-build convenience, not an SDK duration limit. Android offline/live/recreation results do not establish iPhone, longer sustained capture, interruptions or leak-free cleanup.
