# Third-party inventory

This development SDK is independently maintained. Authored wrapper licensing is undecided; publish_to is none. Do not describe the entire archive as MIT.

| Component | Provenance / terms |
|---|---|
| Bundled Tilawa implementation | Commit 2f2617460dc4a6b967e0cc49fa04804bbf22ec69, core metadata 0.4.0. MIT subject to asset exceptions. Preserve assets/runtime/TILAWA_LICENSE and TILAWA_NOTICE.md. |
| Compiled vocabulary / derived constants | Upstream NOTICE's NPL-1.2 asset exceptions still apply when compiled into bridge.js. assets/runtime/NPL-1.2.txt accompanies these artifacts. |
| Model / phoneme corpus / I/O assets | Supplied/installed separately, pinned in prototype/baseline.json and TilawaAssetManifest.zipformerV1. NPL-1.2; model/corpus are not bundled in the SDK archive. Installation requires the accompanying license text. |
| ONNX Runtime Web 1.24.2 JS/WASM | MIT plus preserved ONNXRUNTIME_LICENSE and ONNXRUNTIME_ThirdPartyNotices.txt under assets/runtime. |
| Flutter/WebView/record/path/crypto dependencies | Their own package licenses; resolved versions recorded in pubspec.lock. Flutter consumers include applicable dependency notices. |
| Benchmark audio | Private feasibility probe only, not SDK assets. Redistribution provenance remains under review. |

NPL-1.2 conditions apply to powered features even when assets are downloaded separately. See the full license and PLAN.md section 9. Qiyam's powered features are intended to remain free. This development checkpoint is not authorization for publication or a final license choice.
