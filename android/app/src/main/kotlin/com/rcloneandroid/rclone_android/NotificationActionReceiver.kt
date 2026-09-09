package com.rcloneandroid.rclone_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != RcloneService.ACTION_CANCEL) return
        RcloneService.cancelAll()
        EventHub.log("info", "已从通知取消传输")
    }
}
