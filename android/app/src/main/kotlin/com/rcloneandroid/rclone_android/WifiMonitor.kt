package com.rcloneandroid.rclone_android

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

data class VpnInfo(
    val iface: String?,
    val packageName: String?,
    val label: String?,
) {
    val keys: List<String> get() = listOfNotNull(packageName, label, iface)
    val preferred: String get() = label ?: packageName ?: iface ?: "vpn"
    val fingerprint: String get() = keys.joinToString("|").ifBlank { preferred }
}

@Suppress("DEPRECATION")
class WifiMonitor private constructor(context: Context) {
    private val app = context.applicationContext
    private val cm = app.getSystemService(ConnectivityManager::class.java)
    private var lastSsid: String? = null
    private var lastWifiUp = false
    private var lastVpns: Set<String> = emptySet()
    private var wifiRegistered = false
    private var vpnRegistered = false
    private val wifiNets = mutableSetOf<Network>()
    private val vpnTracks = mutableMapOf<Network, VpnInfo>()

    private val wifiCallback: ConnectivityManager.NetworkCallback =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            object : ConnectivityManager.NetworkCallback(FLAG_INCLUDE_LOCATION_INFO) {
                override fun onAvailable(network: Network) {
                    wifiNets += network
                }
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    onWifiCapabilities(network, caps)
                }
                override fun onLost(network: Network) = onWifiLost(network)
            }
        } else {
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    wifiNets += network
                }
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    onWifiCapabilities(network, caps)
                }
                override fun onLost(network: Network) = onWifiLost(network)
            }
        }

    private val vpnCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            onVpnCapabilities(network, caps)
        }
        override fun onLinkPropertiesChanged(network: Network, props: LinkProperties) {
            onVpnLink(network, props)
        }
        override fun onLost(network: Network) = onVpnLost(network)
    }

    fun start() {
        lastSsid = currentSsid()
        lastWifiUp = lastSsid != null || hasWifiTransport()
        lastVpns = currentVpns().map { it.fingerprint }.toSet()
        if (!wifiRegistered) {
            cm.registerNetworkCallback(wifiRequest(), wifiCallback)
            wifiRegistered = true
        }
        if (!vpnRegistered) {
            cm.registerNetworkCallback(vpnRequest(), vpnCallback)
            vpnRegistered = true
        }
        val vpnText = currentVpns().joinToString("、") { it.preferred }.ifBlank { "无" }
        EventHub.log(
            "info",
            "网络监听已启动，WiFi=${lastSsid ?: "无"} VPN=$vpnText ${diagnose()["wifiHint"]}",
        )
    }

    fun stop() {
        if (wifiRegistered) {
            runCatching { cm.unregisterNetworkCallback(wifiCallback) }
            wifiRegistered = false
        }
        if (vpnRegistered) {
            runCatching { cm.unregisterNetworkCallback(vpnCallback) }
            vpnRegistered = false
        }
    }

    fun currentSsid(androidOnly: Boolean = false): String? {
        val active = cm.activeNetwork
        ssidFromNetwork(active, cm.getNetworkCapabilities(active))?.let { return it }
        for (network in cm.allNetworks) {
            ssidFromNetwork(network, cm.getNetworkCapabilities(network))?.let { return it }
        }
        try {
            val wm = app.getSystemService(WifiManager::class.java)
            sanitize(wm.connectionInfo?.ssid)?.let { return it }
        } catch (_: Exception) {
        }
        return if (androidOnly) null else rootSsid()
    }

    fun currentVpns(): List<VpnInfo> {
        val out = mutableListOf<VpnInfo>()
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            val iface = cm.getLinkProperties(network)?.interfaceName
            var pkg: String? = null
            var label: String? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val uid = caps.ownerUid
                if (uid > 0) {
                    pkg = runCatching { app.packageManager.getPackagesForUid(uid)?.firstOrNull() }.getOrNull()
                    if (pkg != null) {
                        label = runCatching {
                            val info = app.packageManager.getApplicationInfo(pkg, 0)
                            app.packageManager.getApplicationLabel(info).toString()
                        }.getOrNull()
                    }
                }
            }
            out += VpnInfo(iface, pkg, label)
        }
        return out.distinctBy { it.fingerprint }
    }

    fun isWifiAssociated(): Boolean {
        if (currentSsid() != null) return true
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return true
        }
        try {
            val info = app.getSystemService(WifiManager::class.java).connectionInfo
            if (info != null && info.networkId != -1) return true
        } catch (_: Exception) {
        }
        return rootWifiUp()
    }

    fun currentVpnSummary(): String? {
        val vpns = currentVpns()
        if (vpns.isEmpty()) return null
        return vpns.joinToString("、") { it.preferred }
    }

    fun diagnose(): Map<String, Any?> {
        val ssid = currentSsid()
        val wifiUp = isWifiAssociated()
        val hint = when {
            ssid != null -> "已识别 $ssid"
            wifiUp -> "已连 WiFi"
            else -> "未连接 WiFi"
        }
        return mapOf(
            "currentSsid" to ssid,
            "currentVpn" to currentVpnSummary(),
            "locationGranted" to false,
            "locationEnabled" to false,
            "nearbyWifiGranted" to false,
            "wifiHint" to hint,
        )
    }

    private fun wifiRequest(): NetworkRequest {
        return NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
    }

    private fun vpnRequest(): NetworkRequest {
        return NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
    }

    private fun hasWifiTransport(): Boolean {
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return true
        }
        return false
    }

    // SSID 只从回调参数读。官方文档禁止在回调里再 getNetworkCapabilities()。
    private fun onWifiCapabilities(network: Network, caps: NetworkCapabilities) {
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return
        wifiNets += network
        val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            sanitize((caps.transportInfo as? WifiInfo)?.ssid)
        } else {
            null
        }
        if (lastWifiUp && (ssid == null || ssid == lastSsid)) {
            if (ssid != null) lastSsid = ssid
            return
        }
        val previous = lastSsid
        lastWifiUp = true
        if (ssid != null) lastSsid = ssid
        val name = ssid ?: "已连接"
        EventHub.log("info", "WiFi 已连接: $name")
        EventHub.emit(mapOf("type" to "wifi", "event" to "connect", "ssid" to name, "previous" to previous))
        WifiRuleEngine.requestReconcile(app, "WiFi 已连接", NetEvent("wifi", "connect", ssid.orEmpty()))
    }

    private fun onWifiLost(network: Network) {
        wifiNets -= network
        if (wifiNets.isNotEmpty()) return
        if (!lastWifiUp && lastSsid == null) return
        val previous = lastSsid
        lastWifiUp = false
        lastSsid = null
        EventHub.log("info", "WiFi 已断开: ${previous ?: "未知"}")
        EventHub.emit(mapOf("type" to "wifi", "event" to "disconnect", "ssid" to previous))
        WifiRuleEngine.requestReconcile(app, "WiFi 已断开", NetEvent("wifi", "disconnect", previous.orEmpty()))
    }

    private fun onVpnCapabilities(network: Network, caps: NetworkCapabilities) {
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return
        val old = vpnTracks[network]
        rememberVpn(network, vpnFromCaps(caps, old))
    }

    private fun onVpnLink(network: Network, props: LinkProperties) {
        val old = vpnTracks[network]
        rememberVpn(
            network,
            VpnInfo(props.interfaceName, old?.packageName, old?.label),
        )
    }

    private fun onVpnLost(network: Network) {
        val old = vpnTracks.remove(network) ?: return
        lastVpns = lastVpns - old.fingerprint
        EventHub.log("info", "VPN 已断开: ${old.preferred}")
        EventHub.emit(mapOf("type" to "vpn", "event" to "disconnect", "vpn" to old.preferred))
        WifiRuleEngine.requestReconcile(app, "VPN 已断开", NetEvent("vpn", "disconnect", old.preferred, old.keys))
    }

    private fun rememberVpn(network: Network, info: VpnInfo) {
        val prev = vpnTracks.put(network, info)
        if (prev != null) {
            lastVpns = lastVpns - prev.fingerprint + info.fingerprint
            return
        }
        if (info.fingerprint in lastVpns) return
        lastVpns = lastVpns + info.fingerprint
        EventHub.log("info", "VPN 已连接: ${info.preferred}")
        EventHub.emit(
            mapOf(
                "type" to "vpn",
                "event" to "connect",
                "vpn" to info.preferred,
                "package" to info.packageName,
                "iface" to info.iface,
            ),
        )
        WifiRuleEngine.requestReconcile(app, "VPN 已连接", NetEvent("vpn", "connect", info.preferred, info.keys))
    }

    private fun vpnFromCaps(caps: NetworkCapabilities, old: VpnInfo?): VpnInfo {
        var pkg = old?.packageName
        var label = old?.label
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val uid = caps.ownerUid
            if (uid > 0) {
                pkg = runCatching { app.packageManager.getPackagesForUid(uid)?.firstOrNull() }.getOrNull() ?: pkg
                if (pkg != null) {
                    label = runCatching {
                        val appInfo = app.packageManager.getApplicationInfo(pkg, 0)
                        app.packageManager.getApplicationLabel(appInfo).toString()
                    }.getOrNull() ?: label
                }
            }
        }
        return VpnInfo(old?.iface, pkg, label)
    }

    private fun ssidFromNetwork(network: Network?, caps: NetworkCapabilities?): String? {
        if (network == null) return null
        if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val info = caps.transportInfo
            if (info is WifiInfo) {
                return sanitize(info.ssid)
            }
        }
        return null
    }

    private fun rootSsid(): String? {
        if (!RootShell.isAvailable()) return null
        val result = RootShell.exec(
            """
            for d in wlan0 wlan1 wifi0; do
              s=${'$'}(iw dev ${'$'}d link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -n 1)
              [ -z "${'$'}s" ] && s=${'$'}(iw ${'$'}d link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -n 1)
              [ -n "${'$'}s" ] && echo "${'$'}s" && exit 0
            done
            exit 1
            """.trimIndent(),
            log = false,
        )
        return sanitize(result.out.firstOrNull())
    }

    private fun rootWifiUp(): Boolean {
        if (!RootShell.isAvailable()) return false
        val result = RootShell.exec(
            """
            for d in wlan0 wlan1 wifi0; do
              iw dev ${'$'}d link 2>/dev/null | grep -q '^Connected' && exit 0
              iw ${'$'}d link 2>/dev/null | grep -q '^Connected' && exit 0
            done
            exit 1
            """.trimIndent(),
            log = false,
        )
        return result.isSuccess
    }

    private fun sanitize(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val ssid = raw.trim().trim('"')
        if (ssid.isEmpty() || ssid == "<unknown ssid>" || ssid == "0x") return null
        return ssid
    }

    companion object {
        @Volatile
        private var instance: WifiMonitor? = null

        fun get(context: Context): WifiMonitor {
            return instance ?: synchronized(this) {
                instance ?: WifiMonitor(context.applicationContext).also { instance = it }
            }
        }
    }
}

data class NetEvent(
    val kind: String,
    val change: String,
    val target: String,
    val keys: List<String> = listOf(target),
)

object WifiRuleEngine {
    @Volatile
    private var generation = 0

    fun requestReconcile(context: Context, reason: String, event: NetEvent? = null) {
        if (event != null) {
            Thread {
                try {
                    Thread.sleep(200)
                    reconcile(context, reason, event)
                } catch (e: Exception) {
                    EventHub.log("error", "核对规则失败: ${e.message}")
                }
            }.start()
            return
        }
        val mine = synchronized(this) { ++generation }
        Thread {
            try {
                Thread.sleep(350)
                if (mine != generation) return@Thread
                reconcile(context, reason, null)
            } catch (e: Exception) {
                EventHub.log("error", "核对规则失败: ${e.message}")
            }
        }.start()
    }

    fun evaluateCurrent(context: Context) = reconcile(context, "核对当前网络", null)

    fun reconcile(context: Context, reason: String, event: NetEvent? = null) {
        val paths = AppPaths(RcloneApp.instance)
        val settings = readObject(paths.settingsFile)
        if (!settings.optBoolean("wifiMonitorEnabled", true)) return
        if (!paths.wifiRulesFile.exists() || !paths.mountsFile.exists()) return
        if (BootHook.isInstalled()) {
            ModuleRuntime.export(context)
            ModuleRuntime.poke(reason)
            ModuleRuntime.syncUi()
            return
        }
        val monitor = WifiMonitor.get(context)
        RootMountManager.syncFromSystem()
        val ssid = monitor.currentSsid()
        val wifiUp = monitor.isWifiAssociated()
        val vpns = monitor.currentVpns()
        val vpnText = vpns.joinToString("、") { it.preferred }.ifBlank { "无" }
        EventHub.log(
            "info",
            "$reason：当前 WiFi=${ssid ?: if (wifiUp) "已连接但未读到名称" else "无"} VPN=$vpnText",
        )

        val rules = try {
            JSONArray(paths.wifiRulesFile.readText().ifBlank { "[]" })
        } catch (_: Exception) {
            return
        }
        val mounts = try {
            JSONArray(paths.mountsFile.readText().ifBlank { "[]" })
        } catch (_: Exception) {
            return
        }
        val mountById = HashMap<String, JSONObject>()
        for (i in 0 until mounts.length()) {
            val item = mounts.getJSONObject(i)
            mountById[item.optString("id")] = item
        }

        val toMount = linkedSetOf<String>()
        val toUnmount = linkedSetOf<String>()
        for (i in 0 until rules.length()) {
            val rule = rules.getJSONObject(i)
            if (!rule.optBoolean("enabled", true)) continue
            val ids = idsOf(rule)
            if (ids.isEmpty()) continue
            val action = rule.optString("action")
            val kind = rule.optString("kind", "wifi").ifBlank { "wifi" }
            val verdict = evaluateRule(rule, ssid, wifiUp, vpns, event)
            if (verdict.active) {
                EventHub.log("info", "规则生效 ${verdict.label} → ${if (action == "unmount") "卸载" else "挂载"}")
                if (action == "unmount") {
                    toUnmount += ids
                } else {
                    toMount += ids
                }
                continue
            }
            if (!kind.equals("both", true) && action != "unmount" && verdict.known) {
                EventHub.log("info", "规则未满足 ${verdict.label} → 卸载")
                toUnmount += ids
            }
        }

        for (id in toMount) {
            if (RootMountManager.isMounted(id)) continue
            val profile = mountById[id] ?: continue
            try {
                if (settings.optBoolean("preferRealMount", true) && RootShell.isAvailable()) {
                    profile.put("enabled", true)
                    RootMountManager.mount(profile)
                }
            } catch (e: Exception) {
                EventHub.log("error", "按规则挂载失败: ${e.message}")
            }
        }
        for (id in toUnmount) {
            if (id in toMount) continue
            if (!RootMountManager.isMounted(id)) continue
            try {
                RootMountManager.unmount(id)
            } catch (e: Exception) {
                EventHub.log("error", "按规则卸载失败: ${e.message}")
            }
        }
        ModuleRuntime.syncUi()
    }

    @Deprecated("use reconcile")
    fun apply(kind: String, trigger: String, target: String, vpn: VpnInfo? = null) {
        requestReconcile(RcloneApp.instance, "网络变化")
    }

    private data class RuleVerdict(val active: Boolean, val known: Boolean, val label: String)

    private data class ClauseVerdict(val active: Boolean, val known: Boolean, val label: String)

    private fun evaluateRule(
        rule: JSONObject,
        ssid: String?,
        wifiUp: Boolean,
        vpns: List<VpnInfo>,
        event: NetEvent?,
    ): RuleVerdict {
        val kind = rule.optString("kind", "wifi").ifBlank { "wifi" }
        val wifi = evalWifi(
            rule.optString("trigger", "connect"),
            rule.optString("ssid"),
            ssid,
            wifiUp,
        )
        val vpnTarget = rule.optString("vpnName").ifBlank {
            if (kind.equals("vpn", true)) rule.optString("ssid") else ""
        }
        val vpnTrigger = rule.optString("vpnTrigger").ifBlank {
            if (kind.equals("vpn", true)) rule.optString("trigger", "connect") else "connect"
        }
        val vpn = evalVpn(vpnTrigger, vpnTarget, vpns)
        if (!kind.equals("both", true)) {
            return if (kind.equals("vpn", true)) {
                RuleVerdict(vpn.active, vpn.known, vpn.label)
            } else {
                RuleVerdict(wifi.active, wifi.known, wifi.label)
            }
        }
        val triggerSource = rule.optString("triggerSource", "vpn").ifBlank { "vpn" }
        val guard = if (triggerSource.equals("vpn", true)) wifi else vpn
        val edge = if (triggerSource.equals("vpn", true)) vpn else wifi
        val edgeTarget = if (triggerSource.equals("vpn", true)) vpnTarget else rule.optString("ssid")
        val edgeChange = if (triggerSource.equals("vpn", true)) vpnTrigger else rule.optString("trigger", "connect")
        val label = "${guard.label} 时${if (edgeChange.equals("disconnect", true)) "关闭" else "开启"}${if (triggerSource.equals("vpn", true)) "VPN" else "WiFi"}"
        if (event == null) {
            return RuleVerdict(false, false, label)
        }
        val fired = guard.active && guard.known &&
            event.kind.equals(triggerSource, true) &&
            event.change.equals(edgeChange, true) &&
            eventMatches(triggerSource, edgeTarget, event) &&
            edge.active
        return RuleVerdict(fired, true, label)
    }

    private fun eventMatches(kind: String, target: String, event: NetEvent): Boolean {
        val expected = target.trim()
        if (expected.isEmpty() || expected == "*" || expected.equals("any", true) || expected.equals("vpn", true)) {
            return true
        }
        if (kind.equals("wifi", true)) {
            return expected.equals(event.target, ignoreCase = true)
        }
        val needle = expected.lowercase()
        return (event.keys + event.target).any {
            it.contains(needle, ignoreCase = true) || needle.contains(it.lowercase())
        }
    }

    private fun evalWifi(trigger: String, target: String, ssid: String?, wifiUp: Boolean): ClauseVerdict {
        val any = target.isBlank() || target == "*" || target.equals("any", true)
        val matched = if (any) wifiUp else currentlyMatches("wifi", target, ssid, emptyList())
        val known = if (any) true else !wifiUp || !ssid.isNullOrBlank()
        val active = if (trigger.equals("disconnect", true)) !matched && known else matched
        val name = if (any) "任意 WiFi" else target
        val whenText = if (trigger.equals("disconnect", true)) "未连接" else "已连接"
        return ClauseVerdict(active, known, "WiFi $name $whenText")
    }

    private fun evalVpn(trigger: String, target: String, vpns: List<VpnInfo>): ClauseVerdict {
        val matched = currentlyMatches("vpn", target.ifBlank { "*" }, null, vpns)
        val active = if (trigger.equals("disconnect", true)) !matched else matched
        val name = if (target.isBlank() || target == "*") "任意 VPN" else target
        val whenText = if (trigger.equals("disconnect", true)) "未连接" else "已连接"
        return ClauseVerdict(active, true, "VPN $name $whenText")
    }

    private fun currentlyMatches(
        kind: String,
        ruleTarget: String,
        ssid: String?,
        vpns: List<VpnInfo>,
    ): Boolean {
        if (kind.equals("wifi", ignoreCase = true)) {
            return !ssid.isNullOrBlank() && ruleTarget.trim().equals(ssid, ignoreCase = true)
        }
        val expected = ruleTarget.trim()
        if (vpns.isEmpty()) return false
        if (expected.isEmpty() || expected == "*" || expected.equals("any", true) || expected.equals("vpn", true)) {
            return true
        }
        val needle = expected.lowercase()
        return vpns.any { vpn ->
            vpn.keys.any { it.contains(needle, ignoreCase = true) || needle.contains(it.lowercase()) }
        }
    }

    private fun idsOf(rule: JSONObject): List<String> {
        val ids = rule.optJSONArray("profileIds") ?: return emptyList()
        return buildList {
            for (j in 0 until ids.length()) {
                val id = ids.optString(j)
                if (id.isNotBlank()) add(id)
            }
        }
    }

    private fun readObject(file: java.io.File): JSONObject {
        if (!file.exists()) return JSONObject()
        return try {
            JSONObject(file.readText().ifBlank { "{}" })
        } catch (_: Exception) {
            JSONObject()
        }
    }
}
