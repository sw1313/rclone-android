package com.rcloneandroid.rclone_android

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object EventHub {
    @Volatile
    var sink: EventChannel.EventSink? = null

    private val main = Handler(Looper.getMainLooper())
    private val timeFmt = SimpleDateFormat("HH:mm:ss", Locale.CHINA)

    fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    fun log(level: String, message: String) {
        val line = "${timeFmt.format(Date())} [$level] $message"
        try {
            val logFile = AppPaths(RcloneApp.instance).logFile
            logFile.parentFile?.mkdirs()
            logFile.appendText("$line\n")
        } catch (_: Exception) {
        }
        emit(
            mapOf(
                "type" to "log",
                "level" to level,
                "message" to message,
                "time" to System.currentTimeMillis(),
            ),
        )
    }
}
