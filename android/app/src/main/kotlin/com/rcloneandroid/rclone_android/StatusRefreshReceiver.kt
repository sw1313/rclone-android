package com.rcloneandroid.rclone_android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class StatusRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION) return
        Thread {
            try {
                ModuleRuntime.syncUi()
            } catch (_: Exception) {
            }
        }.start()
    }

    companion object {
        const val ACTION = "com.rcloneandroid.rclone_android.REFRESH_STATUS"
    }
}
