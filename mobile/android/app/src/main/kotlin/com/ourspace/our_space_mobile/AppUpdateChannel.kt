package com.ourspace.our_space_mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AppUpdateFileProvider : FileProvider()

class AppUpdateChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installed" -> result.success(installed())
            "canInstall" -> result.success(canInstall())
            "allowInstalls" -> result.success(allowInstalls())
            "install" -> result.success(install(call.arguments as? String))
            else -> result.notImplemented()
        }
    }

    private fun folder(): File = File(activity.filesDir, FOLDER).apply { mkdirs() }

    private fun installed(): Map<String, Any?>? =
        try {
            val info = packageInfo()
            val app = activity.applicationInfo
            val source = app.sourceDir
            val single = app.splitSourceDirs.isNullOrEmpty()
            val apk = if (single && source != null && File(source).canRead()) source else null
            mapOf(
                "code" to PackageInfoCompat.getLongVersionCode(info),
                "name" to (info.versionName ?: ""),
                "folder" to folder().absolutePath,
                "apk" to apk,
            )
        } catch (e: Exception) {
            null
        }

    @Suppress("DEPRECATION")
    private fun packageInfo(): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.getPackageInfo(activity.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            activity.packageManager.getPackageInfo(activity.packageName, 0)
        }

    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun allowInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}"),
        )
        return start(intent)
    }

    private fun install(path: String?): Boolean {
        if (path.isNullOrEmpty()) return false
        val target = try {
            File(path).canonicalFile
        } catch (e: Exception) {
            return false
        }
        val root = try {
            folder().canonicalFile
        } catch (e: Exception) {
            return false
        }
        if (target.parentFile != root || !target.isFile || !target.name.endsWith(".apk")) return false
        val uri = try {
            FileProvider.getUriForFile(activity, "${activity.packageName}$AUTHORITY_SUFFIX", target)
        } catch (e: Exception) {
            return false
        }
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return start(intent)
    }

    private fun start(intent: Intent): Boolean =
        try {
            activity.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }

    companion object {
        const val CHANNEL = "our_space/app_update"
        const val FOLDER = "app-update"
        const val AUTHORITY_SUFFIX = ".app_update"
        const val APK_TYPE = "application/vnd.android.package-archive"
    }
}
