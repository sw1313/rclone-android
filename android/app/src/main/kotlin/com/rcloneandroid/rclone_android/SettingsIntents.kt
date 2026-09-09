package com.rcloneandroid.rclone_android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings

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
