package dev.tilawa.flutter;

import ai.onnxruntime.OrtEnvironment;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodChannel;

/** Runtime identity check; inference stays in flutter_onnxruntime's task queue. */
public final class TilawaRuntimePlugin implements FlutterPlugin {
    private MethodChannel channel;

    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "dev.tilawa/runtime");
        channel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("version")) {
                try {
                    result.success(OrtEnvironment.getEnvironment().getVersion());
                } catch (LinkageError | RuntimeException failure) {
                    result.error("runtimeUnavailable", failure.toString(), null);
                }
            } else {
                result.notImplemented();
            }
        });
    }

    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }
}
