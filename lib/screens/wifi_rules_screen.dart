import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../providers/app_providers.dart';
import 'wifi_rule_edit_screen.dart';

class WifiRulesScreen extends ConsumerWidget {
  const WifiRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(wifiRulesProvider);
    final mounts = ref.watch(mountsProvider);
    final status = ref.watch(nativeStatusProvider);

    String names(WifiRule rule) {
      return rule.profileIds
          .map((id) => mounts.where((m) => m.id == id).map((m) => m.name).firstOrNull ?? id)
          .join('、');
    }

    String title(WifiRule rule) {
      String named(String kind, String name) =>
          name.isEmpty || name == '*' ? '任意$kind' : '$kind $name';
      String state(String trigger) => trigger == 'connect' ? '已连接' : '未连接';
      String edge(String kind, String trigger) => trigger == 'connect'
          ? (kind == 'VPN' ? '开启 VPN' : '连上 WiFi')
          : (kind == 'VPN' ? '关闭 VPN' : '断开 WiFi');
      final action = rule.action == 'mount' ? '挂载' : '卸载';
      if (rule.isBoth) {
        final triggerIsVpn = rule.triggerSource == 'vpn';
        final cond = triggerIsVpn
            ? '${named('WiFi', rule.ssid)}${state(rule.wifiTrigger)}'
            : '${named('VPN', rule.resolvedVpnName)}${state(rule.resolvedVpnTrigger)}';
        final trig = triggerIsVpn
            ? edge('VPN', rule.resolvedVpnTrigger)
            : edge('WiFi', rule.wifiTrigger);
        return '$cond 时$trig → $action';
      }
      if (rule.isVpn) {
        return '${named('VPN', rule.resolvedVpnName)}${state(rule.resolvedVpnTrigger)}时$action';
      }
      return '${named('WiFi', rule.ssid)}${state(rule.wifiTrigger)}时$action';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('自动规则'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const WifiRuleEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('添加规则'),
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.wifi),
            title: Text(status.currentSsid == null ? '当前未连接 WiFi' : '当前 WiFi：${status.currentSsid}'),
            subtitle: Text(
              status.currentVpn == null
                  ? '当前没有 VPN'
                  : '当前 VPN：${status.currentVpn}',
            ),
          ),
          const ListTile(
            dense: true,
            leading: Icon(Icons.info_outline),
            title: Text('单条件按当前状态判断。组合规则是「前提已成立时，触发器发生变化才执行」，例如 WiFi 已断开时再开关 VPN。'),
          ),
          const Divider(height: 1),
          Expanded(
            child: rules.isEmpty
                ? const Center(child: Text('还没有自动规则'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: rules.length,
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            rule.isBoth
                                ? Icons.hub_outlined
                                : rule.isVpn
                                    ? Icons.vpn_lock
                                    : Icons.wifi,
                          ),
                          title: Text(title(rule)),
                          subtitle: Text(names(rule).isEmpty ? '未选择挂载配置' : names(rule)),
                          trailing: Switch(
                            value: rule.enabled,
                            onChanged: (v) =>
                                ref.read(wifiRulesProvider.notifier).upsert(rule.copyWith(enabled: v)),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => WifiRuleEditScreen(existing: rule),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
