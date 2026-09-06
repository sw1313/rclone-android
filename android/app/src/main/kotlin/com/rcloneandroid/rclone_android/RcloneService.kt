package com.rcloneandroid.rclone_android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class RcloneService : Service() {
    private var wifiMonitor: WifiMonitor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        enterForeground()
        Thread {
            try {
                BinaryInstaller.install(this)
                BootHook.sync(this)
                RcloneDaemon.start(this)
                RootMountManager.hydrate()
                refreshNotification()
            } catch (e: Exception) {
                EventHub.log("error", "服务启动 rclone 失败: ${e.message}")
            }
        }.start()
        wifiMonitor = WifiMonitor.get(this).also { it.start() }
        scheduleStartupReconcile()
        EventHub.log("info", "前台服务已启动")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getStringExtra(EXTRA_ACTION) == ACTION_REFRESH) {
            refreshNotification()
        } else {
            WifiRuleEngine.requestReconcile(this, "服务启动核对")
        }
        return START_STICKY
    }

    private fun scheduleStartupReconcile() {
        for (delayMs in longArrayOf(500, 5000, 15000)) {
            Thread {
                try {
                    Thread.sleep(delayMs)
                    if (instance == null) return@Thread
                    WifiRuleEngine.reconcile(this, "启动复查 ${delayMs}ms")
                    refreshNotification()
                } catch (_: Exception) {
                }
            }.start()
        }
    }

    override fun onDestroy() {
        wifiMonitor?.stop()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.service_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = getString(R.string.service_channel_desc)
        nm.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "rclone_service"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_ACTION = "action"
        const val ACTION_REFRESH = "refresh"

        @Volatile
        private var instance: RcloneService? = null

        fun isRunning(): Boolean = instance != null

        fun start(context: Context) {
            BootStarter.startServiceNow(context, "应用内启动")
        }

        fun refreshNotification() {
            val service = instance ?: return
            val nm = service.getSystemService(NotificationManager::class.java)
            nm.notify(NOTIFICATION_ID, service.buildNotification())
        }
    }

    private fun enterForeground() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // 只用 specialUse。location 在 Android 16 后台/授权后会 SecurityException 闪退。
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            EventHub.log("error", "进入前台失败: ${t.message}")
        }
    }

    private fun buildNotification(): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val unmount = PendingIntent.getBroadcast(
            this,
            1,
            Intent(this, NotificationActionReceiver::class.java).setAction(NotificationActionReceiver.ACTION_UNMOUNT_ALL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val mounted = RootMountManager.listRecords()
        val text = if (mounted.isEmpty()) {
            if (RcloneDaemon.isRunning()) "rclone 服务运行中，尚未挂载" else "正在启动 rclone…"
        } else {
            "已挂载 ${mounted.size} 项：${mounted.joinToString("、") { it["name"].toString() }}"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rclone)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, "全部卸载", unmount)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}
