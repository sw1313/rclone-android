package com.rcloneandroid.rclone_android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings

object SettingsIntents {
    fun ignoreBattery(activity: Activity): Map<String, Any?> {
        val pkg = activity.packageName
        val ignored = isIgnoringBattery(activity)
        if (ignored) {
            return result(already = true, opened = false, ignored = true, message = "已忽略电池优化")
        }
        val label = activity.applicationInfo.loadLabel(activity.packageManager).toString()
        val page = launch(activity, batteryIntents(pkg, label))
        return result(
            already = false,
            opened = true,
            ignored = false,
            page = page,
            message = "已打开系统页。小米请把本应用省电策略设为「无限制」",
        )
    }

    fun allFilesAccess(activity: Activity): Map<String, Any?> {
        val granted = hasAllFiles()
        if (granted) {
            return result(already = true, opened = false, ignored = true, message = "已授予所有文件访问权限")
        }
        val pkg = activity.packageName
        val page = launch(activity, allFilesIntents(pkg))
        return result(
            already = false,
            opened = true,
            ignored = false,
            page = page,
            message = "已打开系统页，请打开「允许访问所有文件」",
        )
    }

    fun appDetails(activity: Activity): Map<String, Any?> {
        val page = launch(activity, listOf(packageDetails(activity.packageName)))
        return result(already = false, opened = true, ignored = false, page = page, message = "已打开应用设置")
    }

    fun autostart(activity: Activity): Map<String, Any?> {
        val pkg = activity.packageName
        val page = launch(activity, autostartIntents(pkg))
        return result(
            already = false,
            opened = true,
            ignored = false,
            page = page,
            message = "请允许本应用「自启动」。小米不打开这项，开机广播到不了",
        )
    }

    fun isIgnoringBattery(activity: Activity): Boolean {
        val pm = activity.getSystemService(PowerManager::class.java)
        return pm.isIgnoringBatteryOptimizations(activity.packageName)
    }

    fun hasAllFiles(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()
    }

    private fun batteryIntents(pkg: String, label: String): List<Intent> {
        val xiaomi = isXiaomi()
        val request = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).setData(packageUri(pkg))
        val requestBare = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        val listPage = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        val appBattery = Intent("android.settings.APP_BATTERY_SETTINGS").setData(packageUri(pkg))
        val hiddenApps = Intent().setClassName(
            "com.miui.powerkeeper",
            "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
        ).putExtra("package_name", pkg).putExtra("package_label", label)
        val hiddenList = Intent("miui.intent.action.POWER_HIDE_MODE_APP_LIST")
        val details = packageDetails(pkg)
        return if (xiaomi) {
            listOf(hiddenApps, request, requestBare, hiddenList, appBattery, listPage, details)
        } else {
            listOf(request, requestBare, listPage, appBattery, details)
        }
    }

    private fun autostartIntents(pkg: String): List<Intent> {
        val miuiManage = Intent().setClassName(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        val miuiOp = Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT)
        val miuiApp = Intent().setClassName(
            "com.miui.securitycenter",
            "com.miui.appmanager.ApplicationsDetailsActivity",
        ).putExtra("package_name", pkg).putExtra("package_label", "rclone 挂载")
        val hiddenApps = Intent().setClassName(
            "com.miui.powerkeeper",
            "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
        ).putExtra("package_name", pkg).putExtra("package_label", "rclone 挂载")
        return listOf(miuiManage, miuiOp, miuiApp, hiddenApps, packageDetails(pkg))
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

    private fun isXiaomi(): Boolean {
        val brand = Build.BRAND.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        return listOf("xiaomi", "redmi", "poco", "poe").any { brand.contains(it) || manufacturer.contains(it) }
    }

    private fun result(
        already: Boolean,
        opened: Boolean,
        ignored: Boolean,
        message: String,
        page: String = "",
    ): Map<String, Any?> = mapOf(
        "already" to already,
        "opened" to opened,
        "ignored" to ignored,
        "message" to message,
        "page" to page,
    )
}
