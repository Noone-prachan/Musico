package app.sideb.side_b

import android.app.PictureInPictureParams
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.util.Log
import io.flutter.plugin.common.PluginRegistry
import com.ryanheise.audioservice.AudioServiceActivity
import dev.ffmpegkit_maintained.ytdlp.DownloadProgressCallback
import dev.ffmpegkit_maintained.ytdlp.YtDlp
import dev.ffmpegkit_maintained.ytdlp.YtDlpRequest
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.concurrent.thread

class MainActivity : AudioServiceActivity() {
    private var pictureInPictureEnabled = false
    private var permissionResult: MethodChannel.Result? = null
    private val youtubeSearchExecutor = Executors.newSingleThreadExecutor()
    private val youtubeDownloadExecutor = Executors.newCachedThreadPool()

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
            "musico/youtube_search"
        ).setMethodCallHandler { call, result ->
            if (call.method != "search") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val query = call.argument<String>("query")?.trim()
            if (query.isNullOrEmpty()) {
                result.success("""{"entries":[]}""")
                return@setMethodCallHandler
            }
            if (query.length > 200) {
                result.error("invalid_query", "Search query is too long.", null)
                return@setMethodCallHandler
            }

            youtubeSearchExecutor.execute {
                try {
                    val json = searchYouTube(query)
                    runOnUiThread { result.success(json) }
                } catch (error: Exception) {
                    Log.e("MusicoYouTubeSearch", "Android YouTube search failed", error)
                    runOnUiThread {
                        result.error(
                            "youtube_search_failed",
                            error.message ?: "Android yt-dlp could not search YouTube.",
                            null
                        )
                    }
                } catch (error: LinkageError) {
                    Log.e("MusicoYouTubeSearch", "yt-dlp runtime is unavailable", error)
                    runOnUiThread {
                        result.error(
                            "unsupported_runtime",
                            "Keyless YouTube search requires a 64-bit ARM or x86_64 Android device.",
                            null
                        )
                    }
                }
            }
        }
        val youtubeDownloadChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "musico/youtube_download"
        )
        youtubeDownloadChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "qualities" -> {
                    val videoUrl = call.argument<String>("videoUrl")
                    if (videoUrl.isNullOrBlank()) {
                        result.error(
                            "invalid_arguments",
                            "A YouTube video URL is required.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    youtubeDownloadExecutor.execute {
                        try {
                            val info = inspectYouTubeVideo(videoUrl)
                            runOnUiThread { result.success(info) }
                        } catch (error: Exception) {
                            Log.e(
                                "MusicoYouTubeDownload",
                                "Android yt-dlp could not inspect video formats",
                                error
                            )
                            runOnUiThread {
                                result.error(
                                    "youtube_qualities_failed",
                                    error.message
                                        ?: "Android yt-dlp could not inspect video formats.",
                                    null
                                )
                            }
                        } catch (error: LinkageError) {
                            Log.e(
                                "MusicoYouTubeDownload",
                                "yt-dlp runtime is unavailable",
                                error
                            )
                            runOnUiThread {
                                result.error(
                                    "unsupported_runtime",
                                    "YouTube downloads require a 64-bit ARM or x86_64 Android device.",
                                    null
                                )
                            }
                        }
                    }
                }

                "downloadStream" -> {
                    val id = call.argument<String>("id")
                    val url = call.argument<String>("url")
                    val outputTemplate = call.argument<String>("outputTemplate")
                    val formatSelector = call.argument<String>("formatSelector")
                    if (
                        id.isNullOrBlank() ||
                        url.isNullOrBlank() ||
                        outputTemplate.isNullOrBlank() ||
                        formatSelector.isNullOrBlank()
                    ) {
                        result.error(
                            "invalid_arguments",
                            "The YouTube download request is incomplete.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    youtubeDownloadExecutor.execute {
                        try {
                            YtDlp.init(applicationContext)
                            configureAndroidYouTubePlayerClient()
                            val request = YtDlpRequest(url)
                                .setOutputTemplate(outputTemplate)
                                .addOption("--no-playlist")
                                .addOption("--newline")
                                .addOption("-f", formatSelector)
                            val response = YtDlp.execute(
                                request,
                                DownloadProgressCallback { progress, _, _ ->
                                    val fraction = (progress / 100f).coerceIn(0f, 1f)
                                    runOnUiThread {
                                        youtubeDownloadChannel.invokeMethod(
                                            "progress",
                                            mapOf("id" to id, "progress" to fraction.toDouble())
                                        )
                                    }
                                }
                            )
                            if (!response.isSuccess) {
                                val diagnostic = (
                                    response.errorOutput
                                        .ifBlank { response.output }
                                        .lineSequence()
                                        .filter { it.isNotBlank() }
                                        .toList()
                                        .takeLast(5)
                                        .joinToString(" ")
                                )
                                    .replace(Regex("\\s+"), " ")
                                    .take(900)
                                throw IOException(
                                    "yt-dlp failed with exit code ${response.exitCode}." +
                                        if (diagnostic.isBlank()) "" else " $diagnostic"
                                )
                            }
                            val template = File(outputTemplate)
                            val prefix = template.name.substringBefore("%")
                            val output = template.parentFile
                                ?.listFiles()
                                ?.filter {
                                    it.isFile &&
                                        it.name.startsWith(prefix) &&
                                        !it.name.endsWith(".part") &&
                                        !it.name.endsWith(".ytdl")
                                }
                                ?.maxByOrNull { it.lastModified() }
                            if (output == null || output.length() == 0L) {
                                throw IOException(
                                    "yt-dlp finished without creating a media file."
                                )
                            }
                            runOnUiThread { result.success(output.absolutePath) }
                        } catch (error: Exception) {
                            Log.e(
                                "MusicoYouTubeDownload",
                                "Android YouTube media download failed",
                                error
                            )
                            runOnUiThread {
                                result.error(
                                    "youtube_download_failed",
                                    error.message
                                        ?: "Android yt-dlp could not download this media.",
                                    null
                                )
                            }
                        } catch (error: LinkageError) {
                            Log.e(
                                "MusicoYouTubeDownload",
                                "yt-dlp runtime is unavailable",
                                error
                            )
                            runOnUiThread {
                                result.error(
                                    "unsupported_runtime",
                                    "YouTube downloads require a 64-bit ARM or x86_64 Android device.",
                                    null
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
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

    private fun searchYouTube(query: String): String {
        if (Build.SUPPORTED_ABIS.none { it == "arm64-v8a" || it == "x86_64" }) {
            throw IllegalStateException(
                "Keyless YouTube search requires a 64-bit ARM or x86_64 Android device."
            )
        }

        YtDlp.init(applicationContext)
        val downloader = youtubeDownloader(
            extractFlat = "in_playlist",
            skipDownload = true
        )
        val info = downloader.callAttr(
            "extract_info",
            "ytsearch10:$query",
            false
        )
        return encodeYouTubeInfo(downloader, info)
    }

    private fun inspectYouTubeVideo(videoUrl: String): String {
        YtDlp.init(applicationContext)
        configureAndroidYouTubePlayerClient()
        val downloader = youtubeDownloader(skipDownload = true)
        val info = downloader.callAttr("extract_info", videoUrl, false)
        return encodeYouTubeInfo(downloader, info)
    }

    private fun configureAndroidYouTubePlayerClient() {
        val python = Python.getInstance()
        val scope = python.getBuiltins().callAttr("dict")
        python.getBuiltins().callAttr(
            "exec",
            """
            import yt_dlp
            if not hasattr(yt_dlp, "_musico_original_youtubedl"):
                _musico_original_youtubedl = yt_dlp.YoutubeDL
                class _MusicoAndroidYoutubeDL(_musico_original_youtubedl):
                    def __init__(self, params=None, auto_init=True):
                        params = dict(params or {})
                        extractor_args = dict(params.get("extractor_args") or {})
                        youtube_args = dict(extractor_args.get("youtube") or {})
                        youtube_args["player_client"] = ["android"]
                        extractor_args["youtube"] = youtube_args
                        params["extractor_args"] = extractor_args
                        super().__init__(params, auto_init=auto_init)
                yt_dlp._musico_original_youtubedl = _musico_original_youtubedl
                yt_dlp.YoutubeDL = _MusicoAndroidYoutubeDL
            """.trimIndent(),
            scope,
            scope
        )
    }

    private fun youtubeDownloader(
        extractFlat: String? = null,
        skipDownload: Boolean = false
    ) = Python.getInstance().let { python ->
        val options = python.getBuiltins().callAttr("dict")
        if (extractFlat != null) {
            options.callAttr("__setitem__", "extract_flat", extractFlat)
        }
        options.callAttr("__setitem__", "skip_download", skipDownload)
        options.callAttr("__setitem__", "quiet", true)
        options.callAttr("__setitem__", "no_warnings", true)
        options.callAttr("__setitem__", "socket_timeout", 20)
        options.callAttr("__setitem__", "retries", 1)
        python.getModule("yt_dlp").callAttr("YoutubeDL", options)
    }

    private fun encodeYouTubeInfo(
        downloader: PyObject,
        info: PyObject
    ): String {
        val sanitizedInfo = downloader.callAttr("sanitize_info", info)
        return Python.getInstance().getModule("json")
            .callAttr("dumps", sanitizedInfo)
            .toJava(String::class.java)
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
