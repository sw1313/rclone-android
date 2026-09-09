package com.rcloneandroid.rclone_android

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object ModuleRuntime {
    const val MOD_DIR = "/data/adb/modules/rclone-android"

    fun export(context: Context = RcloneApp.instance) {
        try {
            exportInternal(context)
        } catch (e: Exception) {
            EventHub.log("error", "导出模块配置失败: ${e.message}")
        }
    }

    fun poke(reason: String) {
        if (!BootHook.isInstalled()) return
        RootShell.exec(
            "echo reconcile >> $MOD_DIR/cmd && sh $MOD_DIR/watchdog.sh tick >/dev/null 2>&1 &",
        )
    }

    fun command(line: String) {
        if (!BootHook.isInstalled()) {
            throw IllegalStateException("Magisk 模块未安装")
        }
        export()
        val result = RootShell.exec(
            "printf '%s\\n' ${RootShell.shQuote(line)} >> $MOD_DIR/cmd && sh $MOD_DIR/watchdog.sh tick",
        )
        if (!result.isSuccess) {
            throw IllegalStateException(
                (result.err + result.out).joinToString(" ").ifBlank { "模块执行失败" },
            )
        }
        syncUi()
    }

    fun ensureWatchdog() {
        if (!BootHook.isInstalled()) return
        export()
        RootShell.exec("sh $MOD_DIR/service.sh --now")
    }

    fun syncUi() {
        RootMountManager.hydrate()
        MountNotifier.refresh(RcloneApp.instance)
    }

    fun stopWatchdog() {
        RootShell.exec(
            "if [ -f $MOD_DIR/watchdog.pid ]; then kill -9 \$(cat $MOD_DIR/watchdog.pid) 2>/dev/null || true; fi; " +
                "pkill -f $MOD_DIR/watchdog.sh 2>/dev/null || true; " +
                "pkill -f 'inotifyd $MOD_DIR/net.inotify' 2>/dev/null || true",
            log = false,
        )
    }

    private fun exportInternal(context: Context) {
        val paths = AppPaths(context)
        paths.ensureDirs()
        val exportDir = File(paths.filesDir, "module")
        val profileDir = File(exportDir, "profiles")
        val ruleDir = File(exportDir, "rules")
        profileDir.deleteRecursively()
        ruleDir.deleteRecursively()
        profileDir.mkdirs()
        ruleDir.mkdirs()

        val settings = readObject(paths.settingsFile)
        val state = StringBuilder()
        line(state, "pkg", context.packageName)
        line(state, "files_dir", paths.filesDir.absolutePath)
        line(state, "rclone_bin", paths.rcloneBin.absolutePath)
        line(state, "fusermount_bin", paths.fusermountBin.absolutePath)
        line(state, "wifi_monitor", yn(settings.optBoolean("wifiMonitorEnabled", true)))
        line(state, "prefer_real_mount", yn(settings.optBoolean("preferRealMount", true)))
        line(state, "start_on_boot", yn(BootStarter.isStartOnBoot(context)))
        File(exportDir, "state.conf").writeText(state.toString())

        val mounts = readArray(paths.mountsFile)
        for (i in 0 until mounts.length()) {
            val item = mounts.getJSONObject(i)
            val id = item.optString("id")
            if (id.isBlank()) continue
            val flags = item.optJSONObject("flags") ?: JSONObject()
            val remoteName = item.optString("remoteName")
            val remotePath = item.optString("remotePath", "").trim().trimStart('/')
            val remote = if (remotePath.isEmpty()) "$remoteName:" else "$remoteName:$remotePath"
            val text = StringBuilder()
            line(text, "id", id)
            line(text, "name", item.optString("name", id))
            line(text, "remote", remote)
            line(text, "local", item.optString("localPath"))
            line(text, "vfs_cache_mode", jsonString(flags, "vfsCacheMode", "writes"))
            line(text, "vfs_cache_max_size", jsonString(flags, "vfsCacheMaxSize"))
            line(text, "vfs_cache_max_age", jsonString(flags, "vfsCacheMaxAge"))
            line(text, "dir_cache_time", jsonString(flags, "dirCacheTime"))
            line(text, "buffer_size", jsonString(flags, "bufferSize"))
            line(text, "vfs_read_chunk_size", jsonString(flags, "vfsReadChunkSize"))
            line(text, "transfers", jsonString(flags, "transfers"))
            line(text, "checkers", jsonString(flags, "checkers"))
            line(text, "bwlimit", jsonString(flags, "bwlimit"))
            line(text, "uid", jsonString(flags, "uid"))
            line(text, "gid", jsonString(flags, "gid", "9997"))
            line(text, "umask", jsonString(flags, "umask", "0"))
            line(text, "dir_perms", jsonString(flags, "dirPerms", "0771"))
            line(text, "file_perms", jsonString(flags, "filePerms", "0660"))
            line(text, "allow_other", yn(flags.optBoolean("allowOther", true)))
            line(text, "log_level", jsonString(flags, "logLevel", "INFO"))
            line(text, "extra_args", jsonString(flags, "extraArgs"))
            File(profileDir, "$id.conf").writeText(text.toString())
        }

        val rules = readArray(paths.wifiRulesFile)
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            val id = rule.optString("id").ifBlank { "rule-$i" }
            val kind = rule.optString("kind", "wifi").ifBlank { "wifi" }
            val ids = rule.optJSONArray("profileIds") ?: JSONArray()
            val joined = buildList {
                for (j in 0 until ids.length()) {
                    val v = ids.optString(j)
                    if (v.isNotBlank()) add(v)
                }
            }.joinToString(",")
            val vpnName = rule.optString("vpnName").ifBlank {
                if (kind.equals("vpn", true)) rule.optString("ssid") else ""
            }
            val vpnTrigger = rule.optString("vpnTrigger").ifBlank {
                if (kind.equals("vpn", true)) rule.optString("trigger", "connect") else "connect"
            }
            val text = StringBuilder()
            line(text, "id", id)
            line(text, "enabled", yn(rule.optBoolean("enabled", true)))
            line(text, "kind", kind)
            line(text, "ssid", rule.optString("ssid"))
            line(text, "trigger", rule.optString("trigger", "connect"))
            line(text, "vpn_name", vpnName)
            line(text, "vpn_trigger", vpnTrigger)
            line(text, "trigger_source", rule.optString("triggerSource", "vpn"))
            line(text, "action", rule.optString("action", "mount"))
            line(text, "profiles", joined)
            File(ruleDir, "$id.conf").writeText(text.toString())
        }
    }

    private fun line(out: StringBuilder, key: String, value: String) {
        out.append(key).append('=').append(value.replace("\r", " ").replace("\n", " ")).append('\n')
    }

    private fun yn(value: Boolean): String = if (value) "1" else "0"

    private fun jsonString(obj: JSONObject, key: String, default: String = ""): String {
        if (!obj.has(key) || obj.isNull(key)) return default
        val value = obj.opt(key)?.toString()?.trim().orEmpty()
        return if (value.isEmpty() || value == "null") default else value
    }

    private fun readObject(file: File): JSONObject {
        if (!file.exists()) return JSONObject()
        return try {
            JSONObject(file.readText().ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun readArray(file: File): JSONArray {
        if (!file.exists()) return JSONArray()
        return try {
            JSONArray(file.readText().ifBlank { "[]" })
        } catch (_: Exception) {
            JSONArray()
        }
    }
}
