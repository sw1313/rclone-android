package com.rcloneandroid.rclone_android

import com.topjohnwu.superuser.Shell

object RootShell {
    fun isAvailable(): Boolean {
        return try {
            Shell.getShell().isRoot
        } catch (_: Exception) {
            false
        }
    }

    fun request(): Boolean {
        return try {
            Shell.getShell()
            Shell.isAppGrantedRoot() == true && Shell.getShell().isRoot
        } catch (e: Exception) {
            EventHub.log("error", "申请 Root 失败: ${e.message}")
            false
        }
    }

    fun exec(command: String, log: Boolean = true): Shell.Result {
        if (log) EventHub.log("debug", "su: ${command.take(240)}")
        return Shell.cmd(command).exec()
    }

    fun shQuote(value: String): String {
        return "'" + value.replace("'", "'\\''") + "'"
    }
}
