package com.pulse.messenger

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // Friend Alert Sound fix: NotificationService needs a content:// Uri
    // (via the FileProvider declared in AndroidManifest.xml) for cached
    // alert audio, since a raw file:// path into app-private storage isn't
    // readable by the system notification/sound-playback process on API
    // 24+. This channel is the minimal bridge for that one conversion.
    private val alertAudioChannel = "com.pulse.messenger/alert_audio_uri"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, alertAudioChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getContentUri") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("NO_PATH", "path argument missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            applicationContext,
                            "$packageName.alertaudio.fileprovider",
                            File(path)
                        )
                        // Self-grant is a no-op for our own process but keeps
                        // the Uri usable if ever forwarded via an Intent.
                        applicationContext.grantUriPermission(
                            packageName,
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("URI_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
