package com.rcloneandroid.rclone_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object MountNotifier {
    const val CHANNEL_ID = "rclone_mount"
    const val NOTIFICATION_ID = 1003
    const val ACTION_UNMOUNT_ALL = "com.rcloneandroid.rclone_android.UNMOUNT_ALL"

    fun refresh(context: Context) {
        val app = context.applicationContext
        ensureChannel(app)
        val mounted = try {
            RootMountManager.listRecords()
        } catch (_: Exception) {
            emptyList()
        }
        if (!SettingsIntents.notificationsEnabled(app)) return
        val text = if (mounted.isEmpty()) {
            "尚未挂载"
        } else {
            val names = mounted.joinToString("、") {
                it["name"]?.toString().orEmpty().ifBlank { it["id"].toString() }
            }
            "已挂载 ${mounted.size} 项：$names"
        }
        val open = PendingIntent.getActivity(
            app,
            0,
            Intent(app, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rclone)
            .setContentTitle(app.getString(R.string.app_name))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
        if (mounted.isNotEmpty()) {
            val unmount = PendingIntent.getBroadcast(
                app,
                2,
                Intent(app, NotificationActionReceiver::class.java).setAction(ACTION_UNMOUNT_ALL),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.addAction(0, "全部卸载", unmount)
        }
        runCatching { NotificationManagerCompat.from(app).notify(NOTIFICATION_ID, builder.build()) }
    }

    private fun ensureChannel(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.mount_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = context.getString(R.string.mount_channel_desc)
        nm.createNotificationChannel(channel)
    }
}
