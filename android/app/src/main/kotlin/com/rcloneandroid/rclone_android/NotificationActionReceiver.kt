package com.rcloneandroid.rclone_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_UNMOUNT_ALL) return
        Thread {
            try {
                RootMountManager.unmountAll()
                EventHub.log("info", "已从通知全部卸载")
                RcloneService.refreshNotification()
            } catch (e: Exception) {
                EventHub.log("error", "通知卸载失败: ${e.message}")
            }
        }.start()
    }

    companion object {
        const val ACTION_UNMOUNT_ALL = "com.rcloneandroid.rclone_android.UNMOUNT_ALL"
    }
}
