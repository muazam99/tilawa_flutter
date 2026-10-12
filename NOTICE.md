# Third-party inventory

This development SDK is independently maintained. Authored wrapper licensing is undecided; publish_to is none. Do not describe the entire archive as MIT.

| Component | Origin / terms | Distribution location |
|---|---|---|
| Authored Dart SDK, bridge glue, example and platform configuration | Independently authored integration; wrapper/example code license remains an owner decision. No root LICENSE has been chosen. | lib/, tool/, example/lib/, example/android/, example/ios/ |
| Bundled Tilawa implementation | Commit 2f2617460dc4a6b967e0cc49fa04804bbf22ec69, core metadata 0.4.0. MIT subject to asset exceptions. Retain upstream copyright/license and NOTICE. | assets/runtime/bridge.js, TILAWA_LICENSE, TILAWA_NOTICE.md |
| Compiled vocabulary / derived constants | Upstream NOTICE's NPL-1.2 asset exceptions still apply inside compiled bridge.js. Preserve share-alike terms; wrapper licensing cannot relicense these portions. | assets/runtime/bridge.js and NPL-1.2.txt |
| Model / phoneme corpus / I/O assets | NPL-1.2, pinned by size/SHA-256 in TilawaAssetManifest.zipformerV1 and prototype/baseline.json. Total 74,733,380 bytes including the accompanying license. | Downloaded into the consumer's persistent store; not package/example assets. |
| ONNX Runtime Web 1.24.2 JS/WASM | MIT plus third-party terms in its retained notices. | assets/runtime/bridge.js, ort-wasm-simd-threaded.mjs/.wasm, ONNXRUNTIME_LICENSE, ONNXRUNTIME_ThirdPartyNotices.txt |
| Flutter/WebView/record/path/crypto dependencies | Their own package licenses; exact resolution in pubspec.lock. Example adds path_provider directly. Standard Flutter-generated platform scaffold is adapted for this app. | Resolved dependencies; Flutter consumers retain applicable dependency notices. |
| Public example word-label fixture | Nine ayahs/38 labels copied from pinned corpus w[2], a NPL-1.2 derivative distributed under NPL-1.2, without additional terms. The bundled full license accompanies it via the SDK runtime assets. | example/assets/demo_metadata.json; no benchmark audio. |
| Public example page/juz annotations | Example-owned single-page annotations for 112/113 (Madani page604/juz30), checked against the Phase4 fixture. No private pages.json/juz.json file or word-layout dataset is copied or required. Annotations included in the fixture under NPL-1.2 with that derivative. Not a full display edition. | example/assets/demo_metadata.json |
| Private tracking fixture | Pinned corpus labels (NPL-1.2), with developer layout verification provenance/hashes. Kept as historical Phase4 evidence, separate from the public example. | prototype/app/assets/tracking_fixture.json; exclude from publication in5F. |
| Benchmark audio / private inputs | Private feasibility verification only. Redistribution terms are unresolved; no sample audio is proposed for the public example. | prototype/.cache and ignored prototype/app/assets/runtime; exclude in5F. |

NPL-1.2 conditions apply to powered features even when assets are downloaded separately. See the full license and PLAN.md section 9. Qiyam's powered features are intended to remain free. This development checkpoint is not authorization for publication or a final license choice.

## Phase5A baseline (2026-10-12)

Source baseline: local commit45d4798 on master, clean at session start. Runtime integrity authority: assets/runtime/manifest.json (nine artifact payloads,13,392,903 bytes excluding the manifest). Recognition identity: corpus SHA-256 `24360c05ec88fcacf3419c1fe6cd81d69e653326a0bf0e4fb507e7b98fc88127`, segmentation `zipformer-wordInAyah-v1:<corpus SHA-256>`. Pins and runtime artifacts are preserved. Archive size/inclusion are still unmeasured until5F.

Open release decisions: authored-wrapper/example license, actual public repository/support URLs, publisher, final version, measured resource budgets and final runtime acceptance. Package remains0.1.0-dev.1 with publish_to:none. See PLAN section16 for capture/bridge/routes, physical-iPhone, sustained/resources, broader-recognition and16KB runtime gates. This inventory records terms and locations, not final publication clearance.
