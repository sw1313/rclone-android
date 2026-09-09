package com.rcloneandroid.rclone_android

import android.content.Context
import org.json.JSONObject
import java.io.File

object BootStarter {
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
}
