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
      final kind = rule.isVpn ? 'VPN' : 'WiFi';
      final when = rule.trigger == 'connect' ? '已连接时' : '未连接时';
      final action = rule.action == 'mount' ? '挂载' : '卸载';
      return '$kind ${rule.ssid} · $when$action';
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
            title: Text('按“现在连着什么”判断：已经连上会挂，已经断开且还挂着会卸。'),
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
                          leading: Icon(rule.isVpn ? Icons.vpn_lock : Icons.wifi),
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
