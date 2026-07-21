package com.anandnet.harmonymusic

import android.os.Build
import android.os.PowerManager
import android.content.res.Configuration
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.File
import kotlin.system.exitProcess
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var playbackWakeLock: PowerManager.WakeLock? = null
    private lateinit var nearbyConnections: NearbyConnectionsBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nearbyConnections = NearbyConnectionsBridge(this)
        nearbyConnections.attach(flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "harmonymusic/app_platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppInfo" -> result.success(appInfo())
                "getSystemNavigationMode" -> result.success(systemNavigationMode())
                "setKeepScreenAwake" -> {
                    setKeepScreenAwake(call.arguments as? Boolean == true)
                    result.success(null)
                }
                "setPlaybackWakeLock" -> {
                    setPlaybackWakeLock(call.arguments as? Boolean == true)
                    result.success(null)
                }
                "shareText" -> {
                    shareText(call.arguments?.toString().orEmpty())
                    result.success(null)
                }
                "openUrl" -> {
                    openUrl(call.arguments?.toString().orEmpty())
                    result.success(null)
                }
                "installApk" -> {
                    installApk(call.arguments?.toString().orEmpty(), result)
                }
                "restartApp" -> {
                    restartApp(call.arguments as? Boolean != false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::nearbyConnections.isInitialized) {
            nearbyConnections.dispose()
        }
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        restorePortraitSystemBars()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // Flutter can reapply the previous landscape immersive flags after
            // the rotation callback in optimized release builds. Re-show the
            // bars once this portrait window actually owns focus.
            restorePortraitSystemBars()
        }
    }

    private fun restorePortraitSystemBars() {
        if (resources.configuration.orientation != Configuration.ORIENTATION_PORTRAIT) {
            return
        }
        WindowCompat.getInsetsController(window, window.decorView).show(
            WindowInsetsCompat.Type.systemBars()
        )
    }

    private fun appInfo(): Map<String, String> {
        val packageInfo = packageManager.getPackageInfo(packageName, 0)
        val appLabel = packageManager.getApplicationLabel(applicationInfo).toString()
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toString()
        }

        return mapOf(
            "appName" to appLabel,
            "packageName" to packageName,
            "version" to (packageInfo.versionName ?: ""),
            "buildNumber" to versionCode,
        )
    }

    private fun systemNavigationMode(): String {
        return try {
            val resourceId = resources.getIdentifier(
                "config_navBarInteractionMode",
                "integer",
                "android"
            )
            if (resourceId == 0) {
                "unknown"
            } else {
                when (resources.getInteger(resourceId)) {
                    0, 1 -> "buttons"
                    2 -> "gesture"
                    else -> "unknown"
                }
            }
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun setKeepScreenAwake(enable: Boolean) {
        runOnUiThread {
            if (enable) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    private fun setPlaybackWakeLock(enable: Boolean) {
        if (enable) {
            val lock = playbackWakeLock ?: run {
                val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "$packageName:PlaybackWakeLock"
                ).also {
                    it.setReferenceCounted(false)
                    playbackWakeLock = it
                }
            }
            if (!lock.isHeld) {
                lock.acquire()
            }
        } else {
            playbackWakeLock?.let { lock ->
                if (lock.isHeld) {
                    lock.release()
                }
            }
        }
    }

    private fun shareText(text: String) {
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        val chooser = Intent.createChooser(sendIntent, null).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
    }

    private fun openUrl(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (path.isBlank()) {
            result.error("INVALID_APK_PATH", "APK path is empty", null)
            return
        }

        val apkFile = File(path)
        if (!apkFile.exists() || apkFile.length() == 0L) {
            result.error("APK_NOT_FOUND", "APK file does not exist", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                startActivity(settingsIntent)
            } catch (_: Exception) {
                // The Dart side will still show a controlled failure/fallback.
            }
            result.error(
                "INSTALL_PERMISSION_REQUIRED",
                "Allow Harmony Music to install unknown apps, then try again.",
                null
            )
            return
        }

        try {
            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
                putExtra(Intent.EXTRA_RETURN_RESULT, false)
            }
            startActivity(installIntent)
            result.success(null)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    private fun restartApp(terminate: Boolean) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
        }
        if (terminate) {
            finishAndRemoveTask()
            exitProcess(0)
        }
    }
}
