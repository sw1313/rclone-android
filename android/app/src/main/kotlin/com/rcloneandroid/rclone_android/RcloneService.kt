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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.LinkedHashMap

class RcloneService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val transfers = LinkedHashMap<String, Transfer>()

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> cancelAll()
            ACTION_BEGIN -> beginFromIntent(intent)
            ACTION_UPDATE -> updateFromIntent(intent)
            ACTION_END -> endFromIntent(intent)
        }
        if (transfers.isEmpty()) {
            stopAndClear()
            return START_NOT_STICKY
        }
        enterForeground()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun beginFromIntent(intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        transfers[id] = Transfer(
            id = id,
            title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "传输文件" },
            text = intent.getStringExtra(EXTRA_TEXT).orEmpty(),
            progress = intent.getIntExtra(EXTRA_PROGRESS, -1),
            jobId = intent.getIntExtra(EXTRA_JOB, -1).takeIf { it >= 0 },
        )
    }

    private fun updateFromIntent(intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val current = transfers[id] ?: return
        if (intent.hasExtra(EXTRA_TEXT)) current.text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        if (intent.hasExtra(EXTRA_TITLE)) {
            val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
            if (title.isNotBlank()) current.title = title
        }
        if (intent.hasExtra(EXTRA_PROGRESS)) current.progress = intent.getIntExtra(EXTRA_PROGRESS, -1)
        if (intent.hasExtra(EXTRA_JOB)) {
            current.jobId = intent.getIntExtra(EXTRA_JOB, -1).takeIf { it >= 0 }
        }
    }

    private fun endFromIntent(intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val success = intent.getBooleanExtra(EXTRA_SUCCESS, true)
        val text = intent.getStringExtra(EXTRA_TEXT).orEmpty()
        transfers.remove(id)
        if (transfers.isEmpty()) {
            showFinished(success, text.ifBlank { if (success) "传输完成" else "传输失败" })
        }
    }

    private fun cancelAll() {
        val jobs = transfers.values.mapNotNull { it.jobId }
        transfers.clear()
        Thread {
            for (jobId in jobs) stopJob(jobId)
        }.start()
        showFinished(false, "已取消传输")
        stopAndClear()
    }

    private fun enterForeground() {
        val notification = buildProgressNotification() ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (t: Throwable) {
            EventHub.log("error", "进入传输前台失败: ${t.message}")
        }
    }

    private fun buildProgressNotification(): Notification? {
        val items = transfers.values.toList()
        if (items.isEmpty()) return null
        val first = items.first()
        val title = if (items.size == 1) first.title else "正在处理 ${items.size} 项"
        val text = first.text.ifBlank { first.title }
        val progress = first.progress
        val open = openAppIntent()
        val cancel = PendingIntent.getBroadcast(
            this,
            1,
            Intent(this, NotificationActionReceiver::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rclone)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, "取消", cancel)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(100, 0, true)
        }
        return builder.build()
    }

    private fun showFinished(success: Boolean, text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_rclone)
            .setContentTitle(if (success) "传输完成" else "传输结束")
            .setContentText(text)
            .setAutoCancel(true)
            .setOngoing(false)
            .setContentIntent(openAppIntent())
            .build()
        runCatching { ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE) }
        runCatching { nm.notify(DONE_ID, notification) }
    }

    private fun stopAndClear() {
        transfers.clear()
        runCatching { ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE) }
        stopSelf()
    }

    private fun openAppIntent(): PendingIntent {
        return PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

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

    private data class Transfer(
        val id: String,
        var title: String,
        var text: String,
        var progress: Int,
        var jobId: Int?,
    )

    companion object {
        const val CHANNEL_ID = "rclone_transfer"
        const val NOTIFICATION_ID = 1001
        const val DONE_ID = 1002
        const val ACTION_BEGIN = "com.rcloneandroid.rclone_android.TRANSFER_BEGIN"
        const val ACTION_UPDATE = "com.rcloneandroid.rclone_android.TRANSFER_UPDATE"
        const val ACTION_END = "com.rcloneandroid.rclone_android.TRANSFER_END"
        const val ACTION_CANCEL = "com.rcloneandroid.rclone_android.CANCEL_TRANSFER"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_JOB = "jobId"
        const val EXTRA_SUCCESS = "success"

        @Volatile
        private var instance: RcloneService? = null

        fun isRunning(): Boolean = instance?.transfers?.isNotEmpty() == true

        fun begin(
            context: Context,
            id: String,
            title: String,
            text: String,
            progress: Int = -1,
            jobId: Int? = null,
        ) {
            context.applicationContext.startForegroundService(
                Intent(context, RcloneService::class.java)
                    .setAction(ACTION_BEGIN)
                    .putExtra(EXTRA_ID, id)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_TEXT, text)
                    .putExtra(EXTRA_PROGRESS, progress)
                    .putExtra(EXTRA_JOB, jobId ?: -1),
            )
        }

        fun update(
            context: Context,
            id: String,
            text: String? = null,
            title: String? = null,
            progress: Int? = null,
            jobId: Int? = null,
        ) {
            val service = instance
            if (service != null) {
                service.main.post {
                    val current = service.transfers[id] ?: return@post
                    if (text != null) current.text = text
                    if (!title.isNullOrBlank()) current.title = title
                    if (progress != null) current.progress = progress
                    if (jobId != null) current.jobId = jobId.takeIf { it >= 0 }
                    service.enterForeground()
                }
                return
            }
            begin(context, id, title ?: "传输文件", text.orEmpty(), progress ?: -1, jobId)
        }

        fun end(@Suppress("UNUSED_PARAMETER") context: Context, id: String, success: Boolean, text: String) {
            val service = instance ?: return
            service.main.post {
                service.transfers.remove(id)
                if (service.transfers.isEmpty()) {
                    service.showFinished(success, text)
                    service.stopAndClear()
                } else {
                    service.enterForeground()
                }
            }
        }

        fun cancelAll() {
            instance?.main?.post { instance?.cancelAll() }
        }

        private fun stopJob(jobId: Int) {
            try {
                RcloneDaemon.ensureCredentials()
                val url = URL("${RcloneDaemon.url}job/stop")
                val conn = (url.openConnection() as HttpURLConnection)
                conn.requestMethod = "POST"
                conn.connectTimeout = 3000
                conn.readTimeout = 3000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                val token = android.util.Base64.encodeToString(
                    "${RcloneDaemon.user}:${RcloneDaemon.pass}".toByteArray(),
                    android.util.Base64.NO_WRAP,
                )
                conn.setRequestProperty("Authorization", "Basic $token")
                conn.outputStream.use { it.write(JSONObject().put("jobid", jobId).toString().toByteArray()) }
                conn.inputStream.close()
                conn.disconnect()
            } catch (_: Exception) {
            }
        }
    }
}
