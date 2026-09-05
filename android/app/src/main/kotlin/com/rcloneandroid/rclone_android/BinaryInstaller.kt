package com.rcloneandroid.rclone_android

import android.content.Context

object BinaryInstaller {
    fun install(context: Context): Map<String, Any> {
        val paths = AppPaths(context)
        paths.ensureDirs()
        val abi = paths.abi
        runCatching { paths.rcloneBin.setExecutable(true, false) }
        runCatching { paths.fusermountBin.setExecutable(true, false) }
        val rcloneReady = paths.rcloneBin.exists() && paths.rcloneBin.length() > 1024
        val fuseReady = paths.fusermountBin.exists() && paths.fusermountBin.length() > 100
        if (!rcloneReady) {
            EventHub.log("error", "rclone 未从 jniLibs 解出：${paths.rcloneBin.absolutePath}")
        }
        if (!fuseReady) {
            EventHub.log("warn", "fusermount 未从 jniLibs 解出：${paths.fusermountBin.absolutePath}")
        }
        EventHub.log(
            "info",
            "二进制已准备 abi=$abi rclone=$rcloneReady fusermount=$fuseReady lib=${paths.nativeLibDir}",
        )
        return mapOf(
            "abi" to abi,
            "rcloneReady" to rcloneReady,
            "fusermountReady" to fuseReady,
            "binariesReady" to rcloneReady,
            "rclonePath" to paths.rcloneBin.absolutePath,
        )
    }
}
