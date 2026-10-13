package dev.qiyam.tilawa_bridge_probe

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.os.Build
import android.webkit.WebView
import android.os.Debug
import android.os.PowerManager
import android.app.KeyguardManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

class MainActivity : FlutterActivity() {
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }
    private var probeFocus: AudioFocusRequest? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.qiyam.tilawa_bridge_probe/diagnostics")
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                if (call.method == "destroyWebView") {
                    val identifier = (call.arguments as? Number)?.toLong()
                    val view = identifier?.let { WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, it) }
                    if (view == null) {
                        result.error("missingWebView", "Owned WebView not found", null)
                    } else {
                        view.stopLoading()
                        view.removeJavascriptInterface("TilawaSdk")
                        view.destroy()
                        result.success(null)
                    }
                } else if (call.method == "webDebugging") {
                    WebView.setWebContentsDebuggingEnabled(call.arguments == true)
                    result.success(null)
                } else if (call.method == "takeFocus") {
                    // A competing real Android audio-focus owner, diagnostic only.
                    val granted = if (Build.VERSION.SDK_INT >= 26) {
                        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                            .setAudioAttributes(AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                            .setOnAudioFocusChangeListener(focusListener).build()
                        probeFocus = request
                        audio.requestAudioFocus(request)
                    } else {
                        @Suppress("DEPRECATION")
                        audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC,
                            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    }
                    result.success(granted)
                } else if (call.method == "releaseFocus") {
                    releaseFocus(audio)
                    result.success(null)
                } else if (call.method != "snapshot") {
                    result.notImplemented()
                } else {
                    val memory = Debug.MemoryInfo()
                    Debug.getMemoryInfo(memory)
                    result.success(mapOf(
                        "appPssKiB" to memory.totalPss,
                        "interactive" to (getSystemService(POWER_SERVICE) as PowerManager).isInteractive,
                        "keyguardLocked" to (getSystemService(KEYGUARD_SERVICE) as KeyguardManager).isKeyguardLocked,
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

    private fun releaseFocus(audio: AudioManager) {
        if (Build.VERSION.SDK_INT >= 26) {
            probeFocus?.let { audio.abandonAudioFocusRequest(it) }
            probeFocus = null
        } else {
            @Suppress("DEPRECATION")
            audio.abandonAudioFocus(focusListener)
        }
    }

    override fun onDestroy() {
        releaseFocus(getSystemService(AUDIO_SERVICE) as AudioManager)
        super.onDestroy()
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
