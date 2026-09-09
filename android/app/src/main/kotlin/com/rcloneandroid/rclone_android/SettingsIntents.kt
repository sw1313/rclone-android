package com.rcloneandroid.rclone_android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

object SettingsIntents {
    fun allFilesAccess(activity: Activity): Map<String, Any?> {
        val granted = hasAllFiles()
        if (granted) {
            return result(already = true, opened = false, message = "已授予所有文件访问权限")
        }
        val pkg = activity.packageName
        val page = launch(activity, allFilesIntents(pkg))
        return result(
            already = false,
            opened = true,
            page = page,
            message = "已打开系统页，请打开「允许访问所有文件」",
        )
    }

    fun appDetails(activity: Activity): Map<String, Any?> {
        val page = launch(activity, listOf(packageDetails(activity.packageName)))
        return result(already = false, opened = true, page = page, message = "已打开应用设置")
    }

    fun hasAllFiles(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()
    }

    fun notificationsEnabled(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun requestNotifications(activity: Activity): Map<String, Any?> {
        if (notificationsEnabled(activity)) {
            return result(already = true, opened = false, message = "已允许通知")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            val prefs = activity.getSharedPreferences("perms", Context.MODE_PRIVATE)
            val asked = prefs.getBoolean("notif_asked", false)
            val rationale = ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.POST_NOTIFICATIONS,
            )
            if (!asked || rationale) {
                prefs.edit().putBoolean("notif_asked", true).apply()
                ActivityCompat.requestPermissions(
                    activity,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    4401,
                )
                return result(already = false, opened = true, message = "请在弹窗中允许通知")
            }
        }
        val page = launch(activity, notificationIntents(activity))
        return result(
            already = false,
            opened = true,
            page = page,
            message = "已打开通知设置，请打开「允许通知」",
        )
    }

    fun openNotificationSettings(activity: Activity): Map<String, Any?> {
        val page = launch(activity, notificationIntents(activity))
        return result(
            already = notificationsEnabled(activity),
            opened = true,
            page = page,
            message = "已打开通知设置",
        )
    }

    private fun allFilesIntents(pkg: String): List<Intent> {
        val targeted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).setData(packageUri(pkg))
        } else {
            null
        }
        val targetedParts = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).setData(Uri.fromParts("package", pkg, null))
        } else {
            null
        }
        val allApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
        } else {
            null
        }
        return listOfNotNull(targeted, targetedParts, allApps, packageDetails(pkg))
    }

    private fun notificationIntents(activity: Activity): List<Intent> {
        val pkg = activity.packageName
        val uid = activity.applicationInfo.uid
        val appPage = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
            .putExtra("app_package", pkg)
            .putExtra("app_uid", uid)
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                .putExtra(Settings.EXTRA_CHANNEL_ID, MountNotifier.CHANNEL_ID)
        } else {
            null
        }
        return listOfNotNull(appPage, channel, packageDetails(pkg))
    }

    private fun launch(activity: Activity, intents: List<Intent>): String {
        val errors = mutableListOf<String>()
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                activity.startActivity(intent)
                return intent.component?.className ?: intent.action ?: "opened"
            } catch (e: Exception) {
                errors.add("${intent.action ?: intent.component}: ${e.message}")
            }
        }
        throw IllegalStateException(errors.joinToString("; ").ifEmpty { "没有可用的系统设置页" })
    }

    private fun packageDetails(pkg: String): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(packageUri(pkg))
    }

    private fun packageUri(pkg: String): Uri = Uri.parse("package:$pkg")

    private fun result(
        already: Boolean,
        opened: Boolean,
        message: String,
        page: String = "",
    ): Map<String, Any?> = mapOf(
        "already" to already,
        "opened" to opened,
        "message" to message,
        "page" to page,
    )
}
