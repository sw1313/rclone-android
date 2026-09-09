package com.rcloneandroid.rclone_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            RcloneService.ACTION_CANCEL -> {
                RcloneService.cancelAll()
                EventHub.log("info", "已从通知取消传输")
            }
            MountNotifier.ACTION_UNMOUNT_ALL -> {
                val pending = goAsync()
                Thread {
                    try {
                        RootMountManager.unmountAll()
                        EventHub.log("info", "已从通知全部卸载")
                        MountNotifier.refresh(context)
                    } catch (e: Exception) {
                        EventHub.log("error", "通知卸载失败: ${e.message}")
                    } finally {
                        pending.finish()
                    }
                }.start()
            }
        }
    }
}
