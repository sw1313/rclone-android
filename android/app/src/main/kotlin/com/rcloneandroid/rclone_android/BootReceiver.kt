package com.rcloneandroid.rclone_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
            return
        }
        val settingsFile = AppPaths(context).settingsFile
        val startOnBoot = try {
            val obj = if (!settingsFile.exists()) {
                JSONObject()
            } else {
                JSONObject(settingsFile.readText().ifBlank { "{}" })
            }
            obj.optBoolean("startOnBoot", obj.optBoolean("restoreOnBoot", true))
        } catch (_: Exception) {
            true
        }
        if (!startOnBoot) return
        EventHub.log("info", "开机广播，启动 rclone 服务（按当前网络核对规则）")
        RcloneService.start(context)
    }
}
