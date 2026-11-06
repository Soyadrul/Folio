package com.github.Soyadrul.Folio

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Forwards the hardware volume keys to Flutter while a book is open and
 * delivers EPUB files opened from other apps.
 *
 * Flutter enables the volume keys through the `folio/volume` channel. When
 * disabled the keys fall through to Android, so the system volume slider works
 * normally in the library and in Settings.
 *
 * Files arrive through `folio/intents`: the activity copies `content://` URIs
 * into its cache and hands Dart a normal file path. Before Dart is ready the
 * paths are queued and returned by the `ready` call, so an intent that starts
 * the app is not lost.
 */
class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var intentChannel: MethodChannel? = null
    private var volumeKeysEnabled = false
    private var lastVolumeEventAt = 0L
    private var initialUriString: String? = null
    private var dartReady = false
    private val pendingFiles = ArrayDeque<String>()
    private val pendingUris = ArrayDeque<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        // The launch intent must be captured before super.onCreate(), because
        // configureFlutterEngine() runs inside it and Dart may ask for the
        // pending file very soon afterwards.
        initialUriString = intent?.dataString
        super.onCreate(savedInstanceState)
    }

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
        intentChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "folio/intents",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        dartReady = true
                        val files = pendingFiles.toList()
                        pendingFiles.clear()
                        result.success(files)
                        initialUriString?.let { uri ->
                            initialUriString = null
                            processUri(uri)
                        }
                        while (pendingUris.isNotEmpty()) {
                            processUri(pendingUris.removeFirst())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = intent.dataString ?: return
        if (dartReady) processUri(uri) else pendingUris.addLast(uri)
    }

    /** Materialises [uriString] off the main thread, then hands it to Dart. */
    private fun processUri(uriString: String) {
        val uri = Uri.parse(uriString)
        Thread {
            val path = try {
                materialize(uri)
            } catch (_: Exception) {
                null
            }
            runOnUiThread {
                if (path == null) return@runOnUiThread
                if (dartReady) {
                    intentChannel?.invokeMethod("openFile", path)
                } else {
                    pendingFiles.addLast(path)
                }
            }
        }.start()
    }

    private fun materialize(uri: Uri): String? {
        return when (uri.scheme?.lowercase()) {
            "file" -> uri.path?.takeIf { File(it).isFile }
            "content" -> copyToCache(uri)
            else -> null
        }
    }

    private fun copyToCache(uri: Uri): String? {
        val name = displayName(uri) ?: "book.epub"
        val safeName = name
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "book.epub" }
        val fileName = if (safeName.lowercase().endsWith(".epub")) {
            safeName
        } else {
            "$safeName.epub"
        }
        val dir = File(cacheDir, "incoming")
        if (!dir.exists() && !dir.mkdirs()) return null
        val target = File(dir, "${System.currentTimeMillis()}-$fileName")
        val input = contentResolver.openInputStream(uri) ?: return null
        input.use { source ->
            target.outputStream().use { sink -> source.copyTo(sink) }
        }
        return target.absolutePath
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
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
