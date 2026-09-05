package com.rcloneandroid.rclone_android

import org.json.JSONObject
import java.io.File

object RootMountManager {
    private val mounted = linkedMapOf<String, MountRecord>()

    data class MountRecord(
        val id: String,
        val name: String,
        val localPath: String,
        val fusePoint: String,
        val relative: String?,
    )

    fun listIds(): List<String> {
        syncFromSystem()
        return synchronized(mounted) { mounted.keys.toList() }
    }

    fun isMounted(id: String): Boolean {
        syncFromSystem()
        return synchronized(mounted) { mounted.containsKey(id) }
    }

    fun listRecords(): List<Map<String, Any?>> {
        syncFromSystem()
        return synchronized(mounted) {
            mounted.values.map {
                mapOf(
                    "id" to it.id,
                    "name" to it.name,
                    "localPath" to it.localPath,
                    "fusePoint" to it.fusePoint,
                )
            }
        }
    }

    fun mount(profile: JSONObject): Map<String, Any?> {
        if (!RootShell.request()) {
            throw IllegalStateException("没有 Root 权限，无法真实挂载")
        }
        val paths = AppPaths(RcloneApp.instance)
        paths.ensureDirs()
        if (!paths.rcloneBin.exists() || !paths.fusermountBin.exists()) {
            throw IllegalStateException("rclone 或 fusermount 二进制不可用")
        }

        val id = profile.getString("id")
        val name = profile.optString("name", id)
        val remoteName = profile.getString("remoteName")
        val remotePath = profile.optString("remotePath", "").trim().trimStart('/')
        val localPath = profile.getString("localPath").trim()
        val flags = profile.optJSONObject("flags") ?: JSONObject()
        val remoteSpec = if (remotePath.isEmpty()) "$remoteName:" else "$remoteName:$remotePath"
        val fusePoint = "/mnt/rclone/$id"
        val relative = toEmulatedRelative(localPath)

        unmountInternal(id, localPath, fusePoint, relative, quiet = true)

        val extra = jsonString(flags, "extraArgs")
        val script = File(paths.scriptsDir, "mount-$id.sh")
        script.writeText(buildMountScript(paths, id, remoteSpec, localPath, fusePoint, relative, flags, extra))
        script.setExecutable(true, false)

        val result = RootShell.exec("sh ${RootShell.shQuote(script.absolutePath)}")
        val output = ((result.out + result.err).joinToString("\n")).trim()
        if (output.isNotEmpty()) {
            EventHub.log("info", "mount[$name]: $output")
        }
        if (!result.isSuccess) {
            val logTail = File(paths.logsDir, "mount-$id.log")
                .takeIf { it.exists() }
                ?.readLines()
                ?.takeLast(6)
                ?.joinToString("\n")
                .orEmpty()
            throw IllegalStateException(
                listOf(output, logTail).filter { it.isNotBlank() }.joinToString("\n")
                    .ifEmpty { "挂载失败 (exit ${result.code})" },
            )
        }

        val record = MountRecord(id, name, localPath, fusePoint, relative)
        synchronized(mounted) { mounted[id] = record }
        persistMounted()
        EventHub.log("info", "已挂载 $name -> $localPath")
        EventHub.emit(mapOf("type" to "mount", "id" to id, "mounted" to true, "localPath" to localPath))
        return mapOf("ok" to true, "id" to id, "localPath" to localPath, "fusePoint" to fusePoint)
    }

    fun unmount(id: String): Map<String, Any?> {
        val record = synchronized(mounted) { mounted[id] }
        unmountInternal(id, record?.localPath, record?.fusePoint ?: "/mnt/rclone/$id", record?.relative)
        synchronized(mounted) { mounted.remove(id) }
        persistMounted()
        syncFromSystem()
        synchronized(mounted) { mounted.remove(id) }
        persistMounted()
        EventHub.emit(mapOf("type" to "mount", "id" to id, "mounted" to false))
        EventHub.log("info", "已卸载 $id")
        return mapOf("ok" to true, "id" to id)
    }

    fun unmountAll() {
        syncFromSystem()
        val ids = synchronized(mounted) { mounted.keys.toList() }
        ids.forEach { runCatching { unmount(it) } }
        leftoverCleanup()
        syncFromSystem()
    }

    fun cleanupStale(reason: String) {
        syncFromSystem()
        val ids = synchronized(mounted) { mounted.keys.toList() }
        if (ids.isEmpty() && !hasLeftoverFuse()) return
        EventHub.log("info", "清理残留挂载（$reason）")
        unmountAll()
    }

    fun hydrate() = syncFromSystem()

    fun syncFromSystem() {
        val live = discoverLiveIds()
        val profiles = loadProfiles()
        val bookkeeping = loadBookkeeping()
        val added = mutableListOf<String>()
        val removed = mutableListOf<String>()
        synchronized(mounted) {
            val known = mounted.keys.toSet()
            for (id in known - live) {
                mounted.remove(id)
                removed += id
            }
            for (id in live) {
                if (mounted.containsKey(id)) continue
                val profile = profiles[id]
                val saved = bookkeeping[id]
                val localPath = profile?.optString("localPath")
                    ?.ifBlank { null }
                    ?: saved?.optString("localPath")
                    ?: "/storage/emulated/0/Cloud"
                mounted[id] = MountRecord(
                    id = id,
                    name = profile?.optString("name", id) ?: saved?.optString("name", id) ?: id,
                    localPath = localPath,
                    fusePoint = saved?.optString("fusePoint")?.ifBlank { null } ?: "/mnt/rclone/$id",
                    relative = saved?.optString("relative")?.ifBlank { null } ?: toEmulatedRelative(localPath),
                )
                added += id
            }
        }
        persistMounted()
        for (id in added) {
            EventHub.log("info", "发现实际已挂载 $id")
            EventHub.emit(mapOf("type" to "mount", "id" to id, "mounted" to true))
        }
        for (id in removed) {
            EventHub.emit(mapOf("type" to "mount", "id" to id, "mounted" to false))
        }
    }

    fun restoreEnabled() {
        val paths = AppPaths(RcloneApp.instance)
        if (!paths.mountsFile.exists()) return
        val settings = readJsonObject(paths.settingsFile)
        if (!settings.optBoolean("preferRealMount", true)) {
            EventHub.log("info", "当前为仅文件管理器模式，跳过开机挂载")
            return
        }
        val raw = paths.mountsFile.readText().trim()
        if (raw.isEmpty()) return
        val arr = org.json.JSONArray(raw)
        for (i in 0 until arr.length()) {
            val item = arr.getJSONObject(i)
            if (item.optBoolean("enabled", false)) {
                try {
                    mount(item)
                } catch (e: Exception) {
                    EventHub.log("error", "恢复挂载 ${item.optString("name")} 失败: ${e.message}")
                }
            }
        }
    }

    private fun unmountInternal(
        id: String,
        localPath: String?,
        fusePoint: String,
        relative: String?,
        quiet: Boolean = false,
    ) {
        if (!RootShell.isAvailable() && !quiet) {
            throw IllegalStateException("没有 Root 权限")
        }
        if (!RootShell.isAvailable()) return
        val paths = AppPaths(RcloneApp.instance)
        val script = File(paths.scriptsDir, "unmount-$id.sh")
        val rel = relative ?: localPath?.let { toEmulatedRelative(it) }
        script.writeText(buildUnmountScript(paths, id, localPath, fusePoint, rel))
        script.setExecutable(true, false)
        val quoted = RootShell.shQuote(script.absolutePath)
        val result = RootShell.exec(
            "if command -v timeout >/dev/null 2>&1; then timeout 8 sh $quoted; else sh $quoted; fi",
        )
        if (!quiet && !result.isSuccess) {
            EventHub.log("warn", "卸载 $id: ${(result.out + result.err).joinToString(" ")}")
        }
    }

    private fun buildMountScript(
        paths: AppPaths,
        id: String,
        remoteSpec: String,
        localPath: String,
        fusePoint: String,
        relative: String?,
        flags: JSONObject,
        extra: String,
    ): String {
        val q = RootShell::shQuote
        val cacheMode = jsonString(flags, "vfsCacheMode", "writes").ifBlank { "writes" }
        val cacheMaxSize = jsonString(flags, "vfsCacheMaxSize")
        val cacheMaxAge = jsonString(flags, "vfsCacheMaxAge")
        val dirCacheTime = jsonString(flags, "dirCacheTime")
        val bufferSize = jsonString(flags, "bufferSize")
        val chunkSize = jsonString(flags, "vfsReadChunkSize")
        val transfers = jsonString(flags, "transfers")
        val checkers = jsonString(flags, "checkers")
        val bwlimit = jsonString(flags, "bwlimit")
        val uid = jsonString(flags, "uid")
        val gid = jsonString(flags, "gid", "9997")
        val umask = jsonString(flags, "umask", "0")
        val dirPerms = jsonString(flags, "dirPerms", "0771")
        val filePerms = jsonString(flags, "filePerms", "0660")
        val allowOther = flags.optBoolean("allowOther", true)
        val logLevel = jsonString(flags, "logLevel", "INFO")
        val extraTokens = tokenize(extra)

        val args = mutableListOf(
            q(paths.rcloneBin.absolutePath),
            "mount",
            q(remoteSpec),
            q(fusePoint),
            "--config", q(paths.configFile.absolutePath),
            "--cache-dir", q(paths.vfsCacheDir.absolutePath),
            "--vfs-cache-mode", q(cacheMode),
            "--log-level", q(logLevel),
            "--umask", q(umask),
            "--dir-perms", q(dirPerms),
            "--file-perms", q(filePerms),
        )
        if (gid.isNotBlank()) args += listOf("--gid", q(gid))
        if (uid.isNotBlank()) args += listOf("--uid", q(uid))
        if (allowOther) args += "--allow-other"
        args += "--allow-non-empty"
        if (cacheMaxSize.isNotBlank()) args += listOf("--vfs-cache-max-size", q(cacheMaxSize))
        if (cacheMaxAge.isNotBlank()) args += listOf("--vfs-cache-max-age", q(cacheMaxAge))
        if (dirCacheTime.isNotBlank()) args += listOf("--dir-cache-time", q(dirCacheTime))
        if (bufferSize.isNotBlank()) args += listOf("--buffer-size", q(bufferSize))
        if (chunkSize.isNotBlank()) args += listOf("--vfs-read-chunk-size", q(chunkSize))
        if (transfers.isNotBlank()) args += listOf("--transfers", q(transfers))
        if (checkers.isNotBlank()) args += listOf("--checkers", q(checkers))
        if (bwlimit.isNotBlank()) args += listOf("--bwlimit", q(bwlimit))
        extraTokens.forEach { args += q(it) }

        val bindBlock = buildString {
            if (relative != null) {
                appendLine("REL=${q(relative)}")
                appendLine("for view in write read default; do")
                appendLine("  dest=\"/mnt/runtime/\$view/emulated/0/\$REL\"")
                appendLine("  mkdir -p \"\$dest\"")
                appendLine("  mount -o bind ${q(fusePoint)} \"\$dest\" 2>/dev/null || true")
                appendLine("done")
            }
            appendLine("mkdir -p ${q(localPath)}")
            appendLine("mount -o bind ${q(fusePoint)} ${q(localPath)} 2>/dev/null || true")
        }

        return """
            #!/system/bin/sh
            set -e
            HELPER=/data/local/tmp/rclone-android
            mkdir -p ${'$'}HELPER /mnt/rclone/bin ${q(fusePoint)} ${q(localPath)} ${q(paths.vfsCacheDir.absolutePath)}
            cp -f ${q(paths.fusermountBin.absolutePath)} ${'$'}HELPER/fusermount
            cp -f ${q(paths.fusermountBin.absolutePath)} ${'$'}HELPER/fusermount3
            chmod 755 ${'$'}HELPER/fusermount ${'$'}HELPER/fusermount3
            export PATH=${'$'}HELPER:${q(paths.nativeLibDir.absolutePath)}:/system/bin:/system/xbin:${'$'}PATH
            export HOME=${q(paths.filesDir.absolutePath)}
            export RCLONE_CONFIG=${q(paths.configFile.absolutePath)}
            ${args.joinToString(" ")} >> ${q(File(paths.logsDir, "mount-$id.log").absolutePath)} 2>&1 &
            echo ${'$'}! > ${q("/mnt/rclone/$id.pid")}
            ok=0
            i=0
            while [ ${'$'}i -lt 40 ]; do
              if grep -q ${q(fusePoint)} /proc/mounts 2>/dev/null; then ok=1; break; fi
              sleep 0.25
              i=${'$'}((i+1))
            done
            if [ ${'$'}ok -ne 1 ]; then
              echo "FUSE 挂载未就绪"
              grep -E 'CRITICAL|Fatal|ERROR' ${q(File(paths.logsDir, "mount-$id.log").absolutePath)} | tail -n 3
              exit 1
            fi
            $bindBlock
            echo "mounted $id"
        """.trimIndent()
    }

    private fun buildUnmountScript(
        paths: AppPaths,
        id: String,
        localPath: String?,
        fusePoint: String,
        relative: String?,
    ): String {
        val q = RootShell::shQuote
        return """
            #!/system/bin/sh
            export PATH=/data/local/tmp/rclone-android:${q(paths.nativeLibDir.absolutePath)}:/system/bin:/system/xbin:${'$'}PATH
            lazy() { umount -l "${'$'}1" 2>/dev/null || true; }
            PIDF=${q("/mnt/rclone/$id.pid")}
            if [ -f "${'$'}PIDF" ]; then
              kill -9 ${'$'}(cat "${'$'}PIDF") 2>/dev/null || true
              rm -f "${'$'}PIDF"
            fi
            pkill -9 -f ${q("/mnt/rclone/$id")} 2>/dev/null || true
            ${if (relative != null) """
            REL=${q(relative)}
            for view in write read default; do
              lazy "/mnt/runtime/${'$'}view/emulated/0/${'$'}REL"
            done
            """.trimIndent() else ""}
            ${if (!localPath.isNullOrBlank()) "lazy ${q(localPath)}" else ""}
            lazy ${q(fusePoint)}
            grep -F ${q("/mnt/rclone/$id")} /proc/mounts 2>/dev/null | while read -r _ mp _; do
              [ -n "${'$'}mp" ] && lazy "${'$'}mp"
            done
            grep -F ${q(" $fusePoint ")} /proc/mounts 2>/dev/null | while read -r _ mp _; do
              [ -n "${'$'}mp" ] && lazy "${'$'}mp"
            done
            echo unmounted $id
        """.trimIndent()
    }

    private fun toEmulatedRelative(localPath: String): String? {
        val normalized = localPath.replace('\\', '/').trimEnd('/')
        val prefixes = listOf(
            "/storage/emulated/0/",
            "/sdcard/",
            "/data/media/0/",
            "/mnt/user/0/emulated/0/",
        )
        for (prefix in prefixes) {
            if (normalized.startsWith(prefix)) {
                return normalized.removePrefix(prefix)
            }
        }
        return null
    }

    private fun jsonString(obj: JSONObject, key: String, default: String = ""): String {
        if (!obj.has(key) || obj.isNull(key)) return default
        val value = obj.opt(key)?.toString()?.trim().orEmpty()
        return if (value.isEmpty() || value == "null") default else value
    }

    private fun tokenize(raw: String): List<String> {
        val out = mutableListOf<String>()
        val cur = StringBuilder()
        var quote: Char? = null
        for (ch in raw) {
            when {
                quote != null && ch == quote -> quote = null
                quote == null && (ch == '"' || ch == '\'') -> quote = ch
                quote == null && ch.isWhitespace() -> {
                    if (cur.isNotEmpty()) {
                        out += cur.toString()
                        cur.clear()
                    }
                }
                else -> cur.append(ch)
            }
        }
        if (cur.isNotEmpty()) out += cur.toString()
        return out
    }

    private fun persistMounted() {
        val file = File(AppPaths(RcloneApp.instance).filesDir, "mounted.json")
        val arr = org.json.JSONArray()
        synchronized(mounted) {
            mounted.values.forEach { rec ->
                arr.put(
                    JSONObject()
                        .put("id", rec.id)
                        .put("name", rec.name)
                        .put("localPath", rec.localPath)
                        .put("fusePoint", rec.fusePoint)
                        .put("relative", rec.relative ?: ""),
                )
            }
        }
        file.writeText(arr.toString())
    }

    private fun discoverLiveIds(): Set<String> {
        val text = readProcMounts()
        if (text.isBlank()) return emptySet()
        val profiles = loadProfiles()
        val ids = linkedSetOf<String>()
        for (line in text.lineSequence()) {
            val parts = line.split(Regex("\\s+"))
            if (parts.size < 2) continue
            val source = parts[0]
            val mountPoint = parts[1].replace("\\040", " ")
            val type = parts.getOrNull(2).orEmpty()
            val rclone = type.contains("rclone", ignoreCase = true) ||
                source.contains("fuse.rclone", ignoreCase = true) ||
                (type.startsWith("fuse") && source.contains(':'))
            val marker = "/mnt/rclone/"
            if (mountPoint.startsWith(marker)) {
                val id = mountPoint.removePrefix(marker).substringBefore('/')
                if (id.isNotBlank() && id != "bin") ids += id
                continue
            }
            if (!rclone) continue
            for ((id, profile) in profiles) {
                val local = profile.optString("localPath").trim().trimEnd('/')
                if (local.isNotEmpty() && (mountPoint == local || mountPoint.endsWith("/$local"))) {
                    ids += id
                }
            }
        }
        return ids
    }

    private fun readProcMounts(): String {
        if (RootShell.isAvailable()) {
            val result = RootShell.exec("cat /proc/mounts", log = false)
            val out = result.out.joinToString("\n")
            if (out.isNotBlank()) return out
        }
        return runCatching { File("/proc/mounts").readText() }.getOrDefault("")
    }

    private fun loadProfiles(): Map<String, JSONObject> {
        val file = AppPaths(RcloneApp.instance).mountsFile
        if (!file.exists()) return emptyMap()
        return try {
            val arr = org.json.JSONArray(file.readText().ifBlank { "[]" })
            val map = linkedMapOf<String, JSONObject>()
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                val id = item.optString("id")
                if (id.isNotBlank()) map[id] = item
            }
            map
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun loadBookkeeping(): Map<String, JSONObject> {
        val file = File(AppPaths(RcloneApp.instance).filesDir, "mounted.json")
        if (!file.exists()) return emptyMap()
        return try {
            val arr = org.json.JSONArray(file.readText().ifBlank { "[]" })
            val map = linkedMapOf<String, JSONObject>()
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                val id = item.optString("id")
                if (id.isNotBlank()) map[id] = item
            }
            map
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun leftoverCleanup() {
        if (!RootShell.isAvailable()) return
        RootShell.exec(
            """
            HELPER=/data/local/tmp/rclone-android
            export PATH=${'$'}HELPER:/system/bin:/system/xbin:${'$'}PATH
            for p in /mnt/rclone/*.pid; do
              [ -f "${'$'}p" ] || continue
              kill -9 ${'$'}(cat "${'$'}p") 2>/dev/null || true
              rm -f "${'$'}p"
            done
            pkill -9 -f 'librclone.so mount' 2>/dev/null || true
            grep -E 'fuse\.rclone|/mnt/rclone/' /proc/mounts 2>/dev/null | while read -r _ mp _; do
              [ -n "${'$'}mp" ] || continue
              umount -l "${'$'}mp" 2>/dev/null || true
            done
            """.trimIndent(),
        )
    }

    private fun hasLeftoverFuse(): Boolean = discoverLiveIds().isNotEmpty()

    private fun readJsonObject(file: File): JSONObject {
        if (!file.exists()) return JSONObject()
        return try {
            JSONObject(file.readText().ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
    }
}
