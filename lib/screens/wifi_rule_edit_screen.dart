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
  final _vpnName = TextEditingController();
  String _kind = 'wifi';
  String _wifiTrigger = 'connect';
  String _vpnTrigger = 'connect';
  String _triggerSource = 'vpn';
  String _action = 'mount';
  late Set<String> _ids;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? 'wifi';
    _action = existing?.action ?? 'mount';
    _triggerSource = existing?.triggerSource ?? 'vpn';
    _ids = {...?existing?.profileIds};
    if (existing == null) {
      if (_kind == 'both') {
        _wifiTrigger = 'disconnect';
      }
      return;
    }
    if (existing.kind == 'vpn') {
      _vpnName.text = existing.resolvedVpnName;
      _vpnTrigger = existing.resolvedVpnTrigger;
    } else if (existing.kind == 'both') {
      _ssid.text = existing.ssid;
      _wifiTrigger = existing.trigger;
      _vpnName.text = existing.resolvedVpnName;
      _vpnTrigger = existing.resolvedVpnTrigger;
    } else {
      _ssid.text = existing.ssid;
      _wifiTrigger = existing.trigger;
    }
  }

  @override
  void dispose() {
    _ssid.dispose();
    _vpnName.dispose();
    super.dispose();
  }

  bool get _usesWifi => _kind == 'wifi' || _kind == 'both';
  bool get _usesVpn => _kind == 'vpn' || _kind == 'both';

  Future<void> _useCurrentWifi() async {
    final ssid = await ref.read(nativeBridgeProvider).getCurrentSsid();
    if (ssid != null) {
      setState(() => _ssid.text = ssid);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('读不到 SSID。请授予定位或附近的设备权限，并已连接 WiFi。')),
      );
    }
  }

  Future<void> _useCurrentVpn() async {
    final vpn = await ref.read(nativeBridgeProvider).getCurrentVpn();
    if (vpn != null && vpn.isNotEmpty) {
      setState(() => _vpnName.text = vpn.split('、').first);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有检测到 VPN。可先连上 VPN，或填写名称 / *')),
      );
    }
  }

  Future<void> _save() async {
    if (_usesWifi && _ssid.text.trim().isEmpty) {
      _ssid.text = '*';
    }
    if (_usesVpn && _vpnName.text.trim().isEmpty) {
      _vpnName.text = '*';
    }
    final rule = WifiRule(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      kind: _kind,
      ssid: _kind == 'vpn' ? _vpnName.text.trim() : _ssid.text.trim(),
      trigger: _kind == 'vpn' ? _vpnTrigger : _wifiTrigger,
      vpnName: _usesVpn ? _vpnName.text.trim() : '',
      vpnTrigger: _usesVpn ? _vpnTrigger : 'connect',
      triggerSource: _kind == 'both' ? _triggerSource : _kind,
      action: _action,
      profileIds: _ids.toList(),
      enabled: widget.existing?.enabled ?? true,
    );
    await ref.read(wifiRulesProvider.notifier).upsert(rule);
    if (mounted) Navigator.of(context).pop();
  }

  Widget _wifiFields({required String title, required String stateLabel, required NativeStatus status}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _ssid,
          decoration: InputDecoration(
            labelText: 'SSID / *',
            hintText: '* 表示任意 WiFi',
            helperText: '当前：${status.currentSsid ?? '无'}',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '使用当前 WiFi',
              onPressed: _useCurrentWifi,
              icon: const Icon(Icons.my_location),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('wifi-$_wifiTrigger'),
          initialValue: _wifiTrigger,
          items: const [
            DropdownMenuItem(value: 'connect', child: Text('该 WiFi 已连接')),
            DropdownMenuItem(value: 'disconnect', child: Text('该 WiFi 未连接 / 已断开')),
          ],
          onChanged: (v) => setState(() => _wifiTrigger = v ?? 'connect'),
          decoration: InputDecoration(labelText: stateLabel, border: const OutlineInputBorder()),
        ),
      ],
    );
  }

  Widget _vpnFields({required String title, required String stateLabel, required NativeStatus status}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _vpnName,
          decoration: InputDecoration(
            labelText: 'VPN 名称 / 包名 / *',
            hintText: '* 表示任意 VPN',
            helperText: '当前：${status.currentVpn ?? '无'}',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '使用当前 VPN',
              onPressed: _useCurrentVpn,
              icon: const Icon(Icons.vpn_lock),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('vpn-$_vpnTrigger'),
          initialValue: _vpnTrigger,
          items: const [
            DropdownMenuItem(value: 'connect', child: Text('开启 / 已连接')),
            DropdownMenuItem(value: 'disconnect', child: Text('关闭 / 已断开')),
          ],
          onChanged: (v) => setState(() => _vpnTrigger = v ?? 'connect'),
          decoration: InputDecoration(labelText: stateLabel, border: const OutlineInputBorder()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mounts = ref.watch(mountsProvider);
    final status = ref.watch(nativeStatusProvider);
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
            key: ValueKey('kind-$_kind'),
            initialValue: _kind,
            items: const [
              DropdownMenuItem(value: 'wifi', child: Text('仅 WiFi')),
              DropdownMenuItem(value: 'vpn', child: Text('仅 VPN')),
              DropdownMenuItem(value: 'both', child: Text('前提状态 + 触发器')),
            ],
            onChanged: (v) => setState(() {
              _kind = v ?? 'wifi';
              if (_kind == 'both') {
                _triggerSource = 'vpn';
                _wifiTrigger = 'disconnect';
              }
            }),
            decoration: const InputDecoration(
              labelText: '规则类型',
              helperText: '「前提 + 触发器」例如：WiFi 已断开时，再开启或关闭 VPN 才执行',
              border: OutlineInputBorder(),
            ),
          ),
          if (_kind == 'both') ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('src-$_triggerSource'),
              initialValue: _triggerSource,
              items: const [
                DropdownMenuItem(value: 'vpn', child: Text('触发器是 VPN 开启 / 关闭')),
                DropdownMenuItem(value: 'wifi', child: Text('触发器是 WiFi 连上 / 断开')),
              ],
              onChanged: (v) => setState(() => _triggerSource = v ?? 'vpn'),
              decoration: const InputDecoration(labelText: '哪一侧作为触发器', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            if (_triggerSource == 'vpn') ...[
              _wifiFields(title: '前提：当前须已成立的 WiFi 状态', stateLabel: '前提 WiFi 状态', status: status),
              const SizedBox(height: 16),
              _vpnFields(title: '触发器：VPN 发生变化时执行', stateLabel: 'VPN 变化', status: status),
            ] else ...[
              _vpnFields(title: '前提：当前须已成立的 VPN 状态', stateLabel: '前提 VPN 状态', status: status),
              const SizedBox(height: 16),
              _wifiFields(title: '触发器：WiFi 发生变化时执行', stateLabel: 'WiFi 变化', status: status),
            ],
          ] else ...[
            if (_usesWifi) ...[
              const SizedBox(height: 16),
              _wifiFields(title: 'WiFi 条件', stateLabel: 'WiFi 状态', status: status),
            ],
            if (_usesVpn) ...[
              const SizedBox(height: 16),
              _vpnFields(title: 'VPN 条件', stateLabel: 'VPN 状态', status: status),
            ],
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('action-$_action'),
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
