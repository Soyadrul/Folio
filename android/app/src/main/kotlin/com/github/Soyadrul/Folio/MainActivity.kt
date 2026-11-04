package com.github.Soyadrul.Folio

import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Forwards the hardware volume keys to Flutter while a book is open.
 *
 * Flutter enables this through the `folio/volume` channel. When disabled the
 * keys fall through to Android, so the system volume slider works normally in
 * the library and in Settings.
 */
class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var volumeKeysEnabled = false
    private var lastVolumeEventAt = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "folio/volume",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        volumeKeysEnabled = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    "isEnabled" -> result.success(volumeKeysEnabled)
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "folio/screen",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isVolumeKey(keyCode: Int): Boolean =
        keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN

    private fun forwardVolumeKey(keyCode: Int): Boolean {
        // Holding a key repeats onKeyDown many times. Consume the repeats but
        // only forward the first event, with a small guard between presses.
        val now = System.currentTimeMillis()
        if (now - lastVolumeEventAt < 150L) return true
        lastVolumeEventAt = now
        val direction = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "volumeUp" else "volumeDown"
        volumeChannel?.invokeMethod(direction, null)
        return true
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (volumeKeysEnabled && isVolumeKey(keyCode)) {
            if (event.repeatCount > 0) return true
            return forwardVolumeKey(keyCode)
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (volumeKeysEnabled && isVolumeKey(keyCode)) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }
}
