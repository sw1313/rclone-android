package com.rcloneandroid.rclone_android

import android.content.Context
import java.io.File

object BootHook {
    private const val MOD_ID = "rclone-android"
    private const val MOD_DIR = "/data/adb/modules/$MOD_ID"
    private const val OLD_SCRIPT = "/data/adb/service.d/rclone-android.sh"
    private val MODULE_FILES = listOf("module.prop", "service.sh", "uninstall.sh")

    fun isInstalled(): Boolean {
        if (!RootShell.isAvailable()) return false
        val result = RootShell.exec(
            "[ -f $MOD_DIR/module.prop ] && [ ! -f $MOD_DIR/disable ] && echo yes || echo no",
            log = false,
        )
        return result.out.joinToString("\n").contains("yes")
    }

    fun sync(context: Context) {
        try {
            syncInternal(context)
        } catch (e: Exception) {
            EventHub.log("error", "同步开机模块失败: ${e.message}")
        }
    }

    private fun syncInternal(context: Context) {
        val enabled = BootStarter.isStartOnBoot(context)
        BootStarter.persistFlag(context, enabled)
        if (!RootShell.isAvailable()) {
            EventHub.log("info", "无 Root，开机自启只能靠系统广播；小米请再打开「自启动」")
            return
        }
        if (!enabled) {
            RootShell.exec("rm -rf $MOD_DIR; rm -f $OLD_SCRIPT")
            EventHub.log("info", "已关闭开机自启，移除 Magisk 模块")
            return
        }
        val staging = File(AppPaths(context).scriptsDir, "magisk-module")
        staging.deleteRecursively()
        staging.mkdirs()
        for (name in MODULE_FILES) {
            val target = File(staging, name)
            context.assets.open("magisk-module/$name").bufferedReader().use { reader ->
                target.writeText(reader.readText().replace("\r\n", "\n"))
            }
        }
        val src = RootShell.shQuote(staging.absolutePath)
        val copy = RootShell.exec(
            "mkdir -p $MOD_DIR && " +
                "cp $src/module.prop $src/service.sh $src/uninstall.sh $MOD_DIR/ && " +
                "chmod 755 $MOD_DIR/service.sh $MOD_DIR/uninstall.sh && " +
                "rm -f $MOD_DIR/disable $MOD_DIR/remove $OLD_SCRIPT",
        )
        if (copy.isSuccess && isInstalled()) {
            EventHub.log("info", "已安装 Magisk 模块 $MOD_DIR，可在 Magisk 里自行删除")
        } else {
            EventHub.log(
                "error",
                "安装 Magisk 开机模块失败: ${(copy.err + copy.out).joinToString(" ").ifBlank { "未知错误" }}",
            )
        }
    }
}
