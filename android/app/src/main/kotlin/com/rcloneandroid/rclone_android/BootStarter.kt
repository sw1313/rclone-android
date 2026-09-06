package com.rcloneandroid.rclone_android

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import org.json.JSONObject
import java.io.File

object BootStarter {
    const val EXTRA_FROM_BOOT = "fromBoot"

    fun isUserUnlocked(context: Context): Boolean {
        val um = context.getSystemService(UserManager::class.java)
        return um?.isUserUnlocked != false
    }

    fun isStartOnBoot(context: Context): Boolean {
        val files = listOf(
            File(context.createDeviceProtectedStorageContext().filesDir, "boot_prefs.json"),
            runCatching { AppPaths(context).settingsFile }.getOrNull(),
        )
        for (file in files) {
            if (file == null || !file.exists()) continue
            try {
                val obj = JSONObject(file.readText().ifBlank { "{}" })
                return obj.optBoolean("startOnBoot", obj.optBoolean("restoreOnBoot", true))
            } catch (_: Exception) {
            }
        }
        return true
    }

    fun persistFlag(context: Context, enabled: Boolean) {
        try {
            val dir = context.createDeviceProtectedStorageContext().filesDir
            dir.mkdirs()
            File(dir, "boot_prefs.json").writeText("""{"startOnBoot":$enabled}""")
        } catch (_: Exception) {
        }
    }

    fun startIfEnabled(context: Context, reason: String) {
        if (!isUserUnlocked(context)) {
            note("info", "设备未解锁，等解锁后再拉服务（$reason）")
            return
        }
        if (!isStartOnBoot(context)) {
            note("info", "开机自启已关闭，忽略 $reason")
            return
        }
        startServiceNow(context, reason)
    }

    fun startServiceNow(context: Context, reason: String) {
        note("info", "后台拉起服务：$reason")
        val app = context.applicationContext
        val intent = Intent(app, RcloneService::class.java).putExtra(EXTRA_FROM_BOOT, true)
        try {
            app.startForegroundService(intent)
        } catch (e: Exception) {
            note("error", "startForegroundService 失败: ${e.message}，8 秒后重试，不打开界面")
            Handler(Looper.getMainLooper()).postDelayed({
                runCatching { app.startForegroundService(intent) }
                    .onFailure { note("error", "重试拉服务仍失败: ${it.message}") }
            }, 8000)
        }
    }

    fun note(level: String, message: String) {
        try {
            EventHub.log(level, message)
        } catch (_: Exception) {
            try {
                val file = File(RcloneApp.instance.filesDir, "logs/app.log")
                file.parentFile?.mkdirs()
                file.appendText("$level $message\n")
            } catch (_: Exception) {
            }
        }
    }
}
