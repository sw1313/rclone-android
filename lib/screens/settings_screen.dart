import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_providers.dart';
import 'logs_screen.dart';
import 'wifi_rules_screen.dart';

class _RcloneVersionTile extends ConsumerWidget {
  const _RcloneVersionTile({required this.fallback});

  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(rcClientProvider);
    return FutureBuilder<String>(
      future: client?.versionLabel(),
      builder: (context, snapshot) {
        final text = snapshot.data?.isNotEmpty == true
            ? snapshot.data!
            : (fallback.isNotEmpty ? fallback : (snapshot.hasError ? '服务已启动，版本待刷新' : '读取中…'));
        return ListTile(
          title: const Text('rclone 版本'),
          subtitle: Text(text),
        );
      },
    );
  }
}

Future<void> _openSetting(
  BuildContext context,
  WidgetRef ref,
  Future<String> Function() action,
) async {
  try {
    final message = await action();
    await ref.read(nativeStatusProvider.notifier).refresh();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打不开系统页：$e')));
    }
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final status = ref.watch(nativeStatusProvider);
    final native = ref.read(nativeBridgeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('优先真实挂载'),
            subtitle: Text(
              status.canRealMount
                  ? '有 Root 时把网盘挂到所选手机路径，其他 App 可访问'
                  : '需要 Root + fusermount。当前不可用，文件管理器仍可使用',
            ),
            value: settings.preferRealMount,
            onChanged: (v) => ref.read(settingsProvider.notifier).update(
                  settings.copyWith(preferRealMount: v),
                ),
          ),
          SwitchListTile(
            title: const Text('开机自启'),
            subtitle: const Text('开机后拉起前台服务。是否挂载看当前 WiFi/VPN 是否匹配规则，不要求“刚好这时连上”'),
            value: settings.startOnBoot,
            onChanged: (v) => ref.read(settingsProvider.notifier).update(
                  settings.copyWith(startOnBoot: v),
                ),
          ),
          SwitchListTile(
            title: const Text('按规则自动挂载/卸载'),
            subtitle: const Text('根据当前 WiFi / VPN 状态执行规则'),
            value: settings.wifiMonitorEnabled,
            onChanged: (v) => ref.read(settingsProvider.notifier).update(
                  settings.copyWith(wifiMonitorEnabled: v),
                ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('WiFi / VPN 规则'),
            subtitle: Text([
              if (status.currentSsid != null) 'WiFi ${status.currentSsid}',
              if (status.currentVpn != null) 'VPN ${status.currentVpn}',
              if (status.currentSsid == null && status.currentVpn == null)
                (status.wifiHint.isEmpty ? '当前未连接' : status.wifiHint),
            ].join(' · ')),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WifiRulesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('日志'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LogsScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('申请 Root'),
            subtitle: Text(status.rootAvailable ? '已获得 Root' : '真实挂载必须授权'),
            onTap: () async {
              final ok = await native.requestRoot();
              await ref.read(nativeStatusProvider.notifier).refresh();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? '已获得 Root' : '未获得 Root')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('忽略电池优化'),
            subtitle: Text(
              status.batteryIgnored
                  ? '已忽略，系统不易杀掉挂载服务'
                  : '未忽略。小米请把省电策略设为「无限制」',
            ),
            trailing: status.batteryIgnored
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.chevron_right),
            onTap: () => _openSetting(
              context,
              ref,
              native.requestIgnoreBattery,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('所有文件访问权限'),
            subtitle: Text(
              status.hasAllFiles ? '已授予' : '挂载到手机目录、下载/上传公共目录需要此权限',
            ),
            trailing: status.hasAllFiles
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.chevron_right),
            onTap: () => _openSetting(
              context,
              ref,
              native.openAllFilesSettings,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('定位 / 附近的设备'),
            subtitle: const Text('Android 读取 WiFi 名称需要这些权限'),
            onTap: () async {
              await Permission.locationWhenInUse.request();
              await Permission.nearbyWifiDevices.request();
            },
          ),
          ListTile(
            leading: const Icon(Icons.app_settings_alt),
            title: const Text('系统应用设置'),
            onTap: () => _openSetting(context, ref, native.openAppSettings),
          ),
          const Divider(),
          _RcloneVersionTile(fallback: status.rcloneVersion),
          ListTile(
            title: const Text('ABI / 配置路径'),
            subtitle: Text('${status.abi}\n${status.configPath}'),
          ),
          ListTile(
            title: const Text('Magisk 提示'),
            subtitle: const Text(
              '若其他 App 看不到挂载目录，请把 Magisk 的挂载命名空间设为「全局」并重启。网断了进 App 关开关即可，会用懒卸载，不应卡死。',
            ),
          ),
        ],
      ),
    );
  }
}
