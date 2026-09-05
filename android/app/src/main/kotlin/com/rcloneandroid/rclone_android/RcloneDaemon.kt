package com.rcloneandroid.rclone_android

import android.content.Context
import android.content.SharedPreferences
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID

object RcloneDaemon {
    private const val PREFS = "rclone_rcd"
    private const val KEY_USER = "user"
    private const val KEY_PASS = "pass"
    private const val KEY_PORT = "port"

    @Volatile
    private var process: Process? = null

    val port: Int get() = prefs().getInt(KEY_PORT, 5572)
    val user: String get() = prefs().getString(KEY_USER, "rclone") ?: "rclone"
    val pass: String get() = prefs().getString(KEY_PASS, "") ?: ""
    val url: String get() = "http://127.0.0.1:$port/"

    private fun prefs(): SharedPreferences {
        return RcloneApp.instance.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    }

    fun ensureCredentials() {
        val p = prefs()
        if (p.getString(KEY_PASS, "").isNullOrEmpty()) {
            p.edit()
                .putString(KEY_USER, "rclone")
                .putString(KEY_PASS, UUID.randomUUID().toString().replace("-", "").take(20))
                .putInt(KEY_PORT, 5572)
                .apply()
        }
    }

    fun isPortOpen(): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress("127.0.0.1", port), 400)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    fun isRunning(): Boolean = isPortOpen()

    fun start(context: Context): Map<String, Any?> {
        val paths = AppPaths(context)
        paths.ensureDirs()
        ensureCredentials()
        if (!paths.rcloneBin.exists()) {
            throw IllegalStateException("rclone 二进制不存在")
        }
        if (isPortOpen()) {
            EventHub.log("info", "rclone rcd 已在运行 $url")
            return status()
        }
        stopStale(paths)
        val log = File(paths.logsDir, "rcd.log")
        val builder = ProcessBuilder(
            paths.rcloneBin.absolutePath,
            "rcd",
            "--rc-addr=127.0.0.1:$port",
            "--rc-user=$user",
            "--rc-pass=$pass",
            "--config=${paths.configFile.absolutePath}",
            "--cache-dir=${paths.vfsCacheDir.absolutePath}",
            "--log-level=INFO",
        )
        builder.directory(paths.filesDir)
        builder.redirectErrorStream(true)
        builder.redirectOutput(ProcessBuilder.Redirect.appendTo(log))
        builder.environment()["HOME"] = paths.filesDir.absolutePath
        builder.environment()["PATH"] = "${paths.binDir.absolutePath}:/system/bin:/system/xbin"
        builder.environment()["RCLONE_CONFIG"] = paths.configFile.absolutePath
        val started = builder.start()
        process = started
        val pid = runCatching {
            Process::class.java.methods.firstOrNull { it.name == "pid" }?.invoke(started)
        }.getOrNull()
        if (pid != null) {
            paths.rcdPidFile.writeText(pid.toString())
        }
        val ok = waitForPort(12_000)
        if (!ok) {
            val tail = if (log.exists()) log.readText().takeLast(800) else ""
            throw IllegalStateException("rclone rcd 启动超时 $tail")
        }
        EventHub.log("info", "rclone rcd 已启动 $url")
        EventHub.emit(mapOf("type" to "daemon", "running" to true))
        return status()
    }

    fun stop() {
        try {
            process?.destroy()
        } catch (_: Exception) {
        }
        process = null
        val paths = AppPaths(RcloneApp.instance)
        val pid = paths.rcdPidFile.takeIf { it.exists() }?.readText()?.trim()?.toLongOrNull()
        if (pid != null) {
            try {
                android.os.Process.killProcess(pid.toInt())
            } catch (_: Exception) {
            }
            try {
                Runtime.getRuntime().exec(arrayOf("kill", "-9", pid.toString())).waitFor()
            } catch (_: Exception) {
            }
        }
        EventHub.log("info", "rclone rcd 已停止")
        EventHub.emit(mapOf("type" to "daemon", "running" to false))
    }

    fun status(): Map<String, Any?> {
        ensureCredentials()
        return mapOf(
            "rcdRunning" to isRunning(),
            "rcdUrl" to url,
            "rcdUser" to user,
            "rcdPass" to pass,
            "rcdPort" to port,
        )
    }

    private fun waitForPort(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (isPortOpen()) return true
            if (process?.isAlive == false) return false
            Thread.sleep(200)
        }
        return isPortOpen()
    }

    private fun stopStale(paths: AppPaths) {
        val pid = paths.rcdPidFile.takeIf { it.exists() }?.readText()?.trim()
        if (!pid.isNullOrEmpty() && File("/proc/$pid").exists()) {
            try {
                Runtime.getRuntime().exec(arrayOf("kill", "-9", pid)).waitFor()
            } catch (_: Exception) {
            }
        }
    }
}
