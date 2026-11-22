package app.sideb.side_b

import android.app.PictureInPictureParams
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.PluginRegistry
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import kotlin.concurrent.thread

class MainActivity : AudioServiceActivity() {
    private var pictureInPictureEnabled = false
    private var permissionResult: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 42031) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "musico/android_setup"
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestPermissions") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val permissions = mutableListOf<String>()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                permissions.add(Manifest.permission.POST_NOTIFICATIONS)
            }
            val denied = permissions.filter {
                ContextCompat.checkSelfPermission(this, it) !=
                    PackageManager.PERMISSION_GRANTED
            }
            if (denied.isEmpty()) {
                result.success(true)
                return@setMethodCallHandler
            }
            permissionResult = result
            ActivityCompat.requestPermissions(
                this,
                denied.toTypedArray(),
                42031
            )
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sideb/picture_in_picture"
        ).setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            pictureInPictureEnabled = call.argument<Boolean>("enabled") ?: false
            result.success(null)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sideb/backup"
        ).setMethodCallHandler { call, result ->
            if (call.method != "copyBackupToUri") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcePath = call.argument<String>("sourcePath")
            val targetUri = call.argument<String>("targetUri")
            if (sourcePath == null || targetUri == null) {
                result.error(
                    "invalid_arguments",
                    "A source file and target URI are required.",
                    null
                )
                return@setMethodCallHandler
            }

            thread(name = "musico-backup-copy") {
                try {
                    val source = File(sourcePath)
                    if (!source.isFile) {
                        throw IOException("The backup archive could not be found.")
                    }
                    val output = contentResolver.openOutputStream(
                        Uri.parse(targetUri),
                        "wt"
                    ) ?: throw IOException(
                        "The selected backup destination could not be opened."
                    )
                    output.use { destination ->
                        FileInputStream(source).buffered().use { input ->
                            input.copyTo(destination, 1024 * 1024)
                        }
                    }
                    runOnUiThread { result.success(null) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error("backup_copy_failed", error.message, null)
                    }
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pictureInPictureEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        }
    }
}
