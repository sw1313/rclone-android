import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../providers/app_providers.dart';

class WifiRuleEditScreen extends ConsumerStatefulWidget {
  const WifiRuleEditScreen({super.key, this.existing});

  final WifiRule? existing;

  @override
  ConsumerState<WifiRuleEditScreen> createState() => _WifiRuleEditScreenState();
}

class _WifiRuleEditScreenState extends ConsumerState<WifiRuleEditScreen> {
  final _ssid = TextEditingController();
  String _kind = 'wifi';
  String _trigger = 'connect';
  String _action = 'mount';
  late Set<String> _ids;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _ssid.text = existing?.ssid ?? '';
    _kind = existing?.kind ?? 'wifi';
    _trigger = existing?.trigger ?? 'connect';
    _action = existing?.action ?? 'mount';
    _ids = {...?existing?.profileIds};
  }

  @override
  void dispose() {
    _ssid.dispose();
    super.dispose();
  }

  Future<void> _useCurrent() async {
    final native = ref.read(nativeBridgeProvider);
    if (_kind == 'vpn') {
      final vpn = await native.getCurrentVpn();
      if (vpn != null && vpn.isNotEmpty) {
        setState(() => _ssid.text = vpn.split('、').first);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前没有检测到 VPN。可先连上 Tailscale，或填写 Tailscale / *')),
        );
      }
      return;
    }
    final ssid = await native.getCurrentSsid();
    if (ssid != null) {
      setState(() => _ssid.text = ssid);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读不到 SSID。请授予定位或附近的设备权限，并已连接 WiFi。')),
      );
    }
  }

  Future<void> _save() async {
    final target = _ssid.text.trim();
    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_kind == 'vpn' ? '请填写 VPN 名称，或填 * 表示任意 VPN' : '请填写 SSID')),
      );
      return;
    }
    final rule = WifiRule(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      kind: _kind,
      ssid: target,
      trigger: _trigger,
      action: _action,
      profileIds: _ids.toList(),
      enabled: widget.existing?.enabled ?? true,
    );
    await ref.read(wifiRulesProvider.notifier).upsert(rule);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mounts = ref.watch(mountsProvider);
    final status = ref.watch(nativeStatusProvider);
    final isVpn = _kind == 'vpn';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加自动规则' : '编辑自动规则'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(wifiRulesProvider.notifier).remove(widget.existing!.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _kind,
            items: const [
              DropdownMenuItem(value: 'wifi', child: Text('WiFi')),
              DropdownMenuItem(value: 'vpn', child: Text('VPN（如 Tailscale）')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? 'wifi'),
            decoration: const InputDecoration(labelText: '网络类型', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ssid,
            decoration: InputDecoration(
              labelText: isVpn ? 'VPN 名称 / 包名 / *' : 'SSID',
              hintText: isVpn ? 'Tailscale 或 *' : null,
              helperText: isVpn
                  ? '可填 Tailscale、com.tailscale.ipn，或 * 表示任意 VPN。当前：${status.currentVpn ?? '无'}。开机时也会按当前是否连着核对。'
                  : '按当前是否连着判断。开机时 WiFi 已经断了、盘还挂着，也会卸掉。',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: isVpn ? '使用当前 VPN' : '使用当前 WiFi',
                onPressed: _useCurrent,
                icon: const Icon(Icons.my_location),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _trigger,
            items: [
              DropdownMenuItem(
                value: 'connect',
                child: Text(isVpn ? '该 VPN 已连接时' : '该 WiFi 已连接时'),
              ),
              DropdownMenuItem(
                value: 'disconnect',
                child: Text(isVpn ? '该 VPN 未连接时' : '该 WiFi 未连接时'),
              ),
            ],
            onChanged: (v) => setState(() => _trigger = v ?? 'connect'),
            decoration: const InputDecoration(labelText: '条件', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _action,
            items: const [
              DropdownMenuItem(value: 'mount', child: Text('挂载所选配置')),
              DropdownMenuItem(value: 'unmount', child: Text('卸载所选配置')),
            ],
            onChanged: (v) => setState(() => _action = v ?? 'mount'),
            decoration: const InputDecoration(labelText: '动作', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text('关联挂载配置', style: Theme.of(context).textTheme.titleMedium),
          if (mounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('还没有挂载配置'),
            ),
          ...mounts.map(
            (m) => CheckboxListTile(
              value: _ids.contains(m.id),
              title: Text(m.name),
              subtitle: Text(m.remoteSpec),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _ids.add(m.id);
                  } else {
                    _ids.remove(m.id);
                  }
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}
