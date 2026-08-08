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

    // Play Ludo feature: launches the integrated native Java Ludo King
    // Clone (package com.vinaykpro.ludoking, source under
    // android/app/src/ludo/java), reached from the home screen's
    // profile-picture menu (My Profile / Play Ludo / Logout — see
    // home_screen.dart). A separate channel from alertAudioChannel above,
    // added independently so neither handler is touched by the other.
    private val ludoChannel = "pulse/ludo"

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ludoChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "startLudo") {
                    try {
                        // Explicit Intent to an internal Activity of this
                        // same application — never an external app launch.
                        // SplashActivity is Ludo's real entry point (it
                        // self-navigates to HomeActivity after its intro
                        // animation; see SplashActivity.java), matching the
                        // original app's own launch flow.
                        val intent = Intent(
                            this,
                            Class.forName("com.vinaykpro.ludoking.SplashActivity")
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("LUDO_LAUNCH_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
