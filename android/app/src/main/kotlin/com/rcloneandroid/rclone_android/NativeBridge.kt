package com.rcloneandroid.rclone_android

import android.app.Activity
import android.content.Intent
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class NativeBridge(private val activity: Activity) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val io = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD).setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, EVENT).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        EventHub.sink = events
    }

    override fun onCancel(arguments: Any?) {
        EventHub.sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        io.execute {
            try {
                val value = handle(call)
                main.post { result.success(value) }
            } catch (e: Exception) {
                EventHub.log("error", "${call.method}: ${e.message}")
                main.post { result.error("native", e.message, null) }
            }
        }
    }

    private fun handle(call: MethodCall): Any? {
        val paths = AppPaths(activity)
        return when (call.method) {
            "prepareBinaries" -> {
                val ready = BinaryInstaller.install(activity)
                BootHook.sync(activity)
                ready
            }
            "getStatus" -> status()
            "startService" -> {
                RcloneService.start(activity)
                BootHook.sync(activity)
                true
            }
            "startRcd" -> RcloneDaemon.start(activity)
            "stopRcd" -> {
                RcloneDaemon.stop()
                true
            }
            "requestRoot" -> RootShell.request()
            "mount" -> {
                val raw = call.argument<Map<String, Any?>>("profile")
                    ?: throw IllegalArgumentException("缺少 profile")
                RootMountManager.mount(JSONObject(raw))
            }
            "unmount" -> {
                val id = call.argument<String>("id") ?: throw IllegalArgumentException("缺少 id")
                RootMountManager.unmount(id)
            }
            "unmountAll" -> {
                RootMountManager.unmountAll()
                true
            }
            "listMounted" -> RootMountManager.listRecords()
            "getCurrentSsid" -> WifiMonitor.get(activity).currentSsid()
            "getCurrentVpn" -> WifiMonitor.get(activity).currentVpnSummary()
            "startWifiMonitor" -> {
                WifiMonitor.get(activity).start()
                true
            }
            "requestIgnoreBattery" -> onMain { SettingsIntents.ignoreBattery(activity) }
            "openAllFilesSettings" -> onMain { SettingsIntents.allFilesAccess(activity) }
            "openLocationSettings" -> onMain {
                activity.startActivity(
                    Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            }
            "openAppSettings" -> onMain { SettingsIntents.appDetails(activity) }
            "openAutostartSettings" -> onMain { SettingsIntents.autostart(activity) }
            "moveTaskToBack" -> onMain {
                activity.moveTaskToBack(true)
                true
            }
            "readFile" -> {
                val name = call.argument<String>("name") ?: throw IllegalArgumentException("缺少 name")
                val file = File(paths.filesDir, name)
                if (file.exists()) file.readText() else call.argument<String>("fallback").orEmpty()
            }
            "writeFile" -> {
                val name = call.argument<String>("name") ?: throw IllegalArgumentException("缺少 name")
                val content = call.argument<String>("content") ?: ""
                val file = File(paths.filesDir, name)
                file.parentFile?.mkdirs()
                file.writeText(content)
                if (name == "settings.json") {
                    BootHook.sync(activity)
                }
                true
            }
            "readConfig" -> if (paths.configFile.exists()) paths.configFile.readText() else ""
            "writeConfig" -> {
                paths.configFile.writeText(call.argument<String>("content") ?: "")
                if (RcloneDaemon.isRunning()) {
                    RcloneDaemon.stop()
                    RcloneDaemon.start(activity)
                }
                true
            }
            "defaultDownloadDir" -> {
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath
            }
            "rcloneVersion" -> rcloneVersion(paths)
            else -> throw IllegalArgumentException("未知方法 ${call.method}")
        }
    }

    private fun status(): Map<String, Any?> {
        val paths = AppPaths(activity)
        paths.ensureDirs()
        val wifi = WifiMonitor.get(activity).diagnose()
        val daemon = RcloneDaemon.status()
        return hashMapOf<String, Any?>(
            "rootAvailable" to RootShell.isAvailable(),
            "binariesReady" to paths.rcloneBin.exists(),
            "rcloneReady" to paths.rcloneBin.exists(),
            "fusermountReady" to paths.fusermountBin.exists(),
            "abi" to paths.abi,
            "filesDir" to paths.filesDir.absolutePath,
            "configPath" to paths.configFile.absolutePath,
            "currentSsid" to wifi["currentSsid"],
            "currentVpn" to wifi["currentVpn"],
            "locationGranted" to (wifi["locationGranted"] == true),
            "locationEnabled" to (wifi["locationEnabled"] == true),
            "nearbyWifiGranted" to (wifi["nearbyWifiGranted"] == true),
            "wifiHint" to (wifi["wifiHint"]?.toString() ?: ""),
            "mountedIds" to RootMountManager.listIds(),
            "mounted" to RootMountManager.listRecords(),
            "serviceRunning" to RcloneService.isRunning(),
            "hasAllFiles" to SettingsIntents.hasAllFiles(),
            "batteryIgnored" to SettingsIntents.isIgnoringBattery(activity),
            "bootHookInstalled" to BootHook.isInstalled(),
            "rcloneVersion" to rcloneVersion(paths),
        ).apply { putAll(daemon) }
    }

    private fun <T> onMain(block: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        val box = arrayOfNulls<Any>(1)
        val error = arrayOfNulls<Throwable>(1)
        val latch = java.util.concurrent.CountDownLatch(1)
        main.post {
            try {
                box[0] = block()
            } catch (t: Throwable) {
                error[0] = t
            } finally {
                latch.countDown()
            }
        }
        if (!latch.await(8, java.util.concurrent.TimeUnit.SECONDS)) {
            throw IllegalStateException("打开系统页超时")
        }
        error[0]?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return box[0] as T
    }

    private fun rcloneVersion(paths: AppPaths): String {
        if (!paths.rcloneBin.exists()) return ""
        return try {
            val proc = ProcessBuilder(paths.rcloneBin.absolutePath, "version")
                .redirectErrorStream(true)
                .start()
            val text = proc.inputStream.bufferedReader().readText()
            proc.waitFor()
            val line = text.lineSequence().firstOrNull().orEmpty().trim()
            if (line.startsWith("rclone", ignoreCase = true) || line.startsWith("v")) {
                line
            } else {
                ""
            }
        } catch (_: Exception) {
            ""
        }
    }

    companion object {
        const val METHOD = "com.rcloneandroid.rclone_android/native"
        const val EVENT = "com.rcloneandroid.rclone_android/events"
    }
}
