import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/runtime_permissions.dart';
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
            subtitle: Text(
              settings.startOnBoot
                  ? (status.bootHookInstalled
                      ? '已安装 Magisk 看门狗，按规则挂载/卸载，不拉起本应用'
                      : '有 Root 时会安装 Magisk 看门狗，不会让本应用开机常驻')
                  : '关闭后会移除 Magisk 模块，重启后不再自动挂载',
            ),
            value: settings.startOnBoot,
            onChanged: (v) async {
              await ref.read(settingsProvider.notifier).update(
                    settings.copyWith(startOnBoot: v),
                  );
              await ref.read(nativeStatusProvider.notifier).refresh();
            },
          ),
          SwitchListTile(
            title: const Text('按规则自动挂载/卸载'),
            subtitle: const Text('单条件按当前状态；组合规则看前提 + 触发器。由 Magisk 看门狗执行，不依赖 App 保活'),
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
              try {
                final ok = await native.requestRoot();
                if (!context.mounted) return;
                await ref.read(nativeStatusProvider.notifier).refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? '已获得 Root' : '未获得 Root')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('申请 Root 失败：$e')),
                  );
                }
              }
            },
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
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('通知（传输进度）'),
            subtitle: const Text('只在下载/上传时显示进度条，完成后消失。不给也能在应用内传输'),
            onTap: () async {
              await RuntimePermissions.requestNotification();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已请求通知权限')),
                );
              }
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
