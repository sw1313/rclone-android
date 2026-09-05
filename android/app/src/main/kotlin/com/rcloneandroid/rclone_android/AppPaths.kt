package com.rcloneandroid.rclone_android

import android.content.Context
import android.os.Build
import java.io.File

class AppPaths(context: Context) {
    private val appContext = context.applicationContext
    val filesDir: File = appContext.filesDir
    val nativeLibDir: File = File(appContext.applicationInfo.nativeLibraryDir)
    val binDir: File = nativeLibDir
    val scriptsDir: File = File(filesDir, "scripts")
    val logsDir: File = File(filesDir, "logs")
    val vfsCacheDir: File = File(filesDir, "vfs")
    val rcloneBin: File = File(nativeLibDir, "librclone.so")
    val fusermountBin: File = File(nativeLibDir, "libfusermount.so")
    val configFile: File = File(filesDir, "rclone.conf")
    val rcdPidFile: File = File(filesDir, "rcd.pid")
    val mountsFile: File = File(filesDir, "mounts.json")
    val wifiRulesFile: File = File(filesDir, "wifi_rules.json")
    val settingsFile: File = File(filesDir, "settings.json")
    val logFile: File = File(logsDir, "app.log")

    val abi: String
        get() {
            val abis = Build.SUPPORTED_ABIS
            return when {
                abis.contains("arm64-v8a") -> "arm64-v8a"
                abis.contains("armeabi-v7a") -> "armeabi-v7a"
                abis.contains("x86_64") -> "x86_64"
                abis.isNotEmpty() -> abis[0]
                else -> "arm64-v8a"
            }
        }

    fun ensureDirs() {
        listOf(scriptsDir, logsDir, vfsCacheDir).forEach { it.mkdirs() }
        if (!configFile.exists()) {
            configFile.writeText("# rclone.conf managed by rclone 挂载\n")
        }
    }
}
