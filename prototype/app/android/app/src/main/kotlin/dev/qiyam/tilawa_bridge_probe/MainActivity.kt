package dev.qiyam.tilawa_bridge_probe

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Debug
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.qiyam.tilawa_bridge_probe/diagnostics")
            .setMethodCallHandler { call, result ->
                if (call.method != "snapshot") {
                    result.notImplemented()
                } else {
                    val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                    val memory = Debug.MemoryInfo()
                    Debug.getMemoryInfo(memory)
                    result.success(mapOf(
                        "appPssKiB" to memory.totalPss,
                        // Android exposes client delivery separately from device-side capture.
                        "recordings" to audio.activeRecordingConfigurations.map { recording ->
                            mapOf(
                                "client" to format(recording.clientFormat),
                                "device" to format(recording.format),
                                "deviceType" to recording.audioDevice?.type,
                                "silenced" to if (android.os.Build.VERSION.SDK_INT >= 29) recording.isClientSilenced else null
                            )
                        }
                    ))
                }
            }
    }

    private fun format(audio: AudioFormat) = mapOf(
        "sampleRate" to audio.sampleRate,
        "channels" to audio.channelCount,
        "encoding" to audio.encoding
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A foreground-only probe needs stable screen/power conditions.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
