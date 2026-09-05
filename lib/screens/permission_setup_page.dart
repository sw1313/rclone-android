import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/app_providers.dart';
import 'app_shell.dart';

class PermissionSetupPage extends ConsumerStatefulWidget {
  const PermissionSetupPage({super.key});

  @override
  ConsumerState<PermissionSetupPage> createState() => _PermissionSetupPageState();
}

class _PermissionSetupPageState extends ConsumerState<PermissionSetupPage>
    with WidgetsBindingObserver {
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptMissing());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(nativeStatusProvider.notifier).refresh();
    }
  }

  Future<void> _promptMissing() async {
    if (_prompted) return;
    _prompted = true;
    await ref.read(nativeStatusProvider.notifier).refresh();
    if (!mounted) return;
    final native = ref.read(nativeBridgeProvider);
    final status = ref.read(nativeStatusProvider);

    if (!status.hasAllFiles) {
      final go = await _confirm(
        title: '需要所有文件访问权限',
        body: '把网盘挂到手机目录、以及文件管理器下载/上传，都需要系统的「所有文件访问」。接下来会打开系统页，请打开开关。',
        action: '去授予',
      );
      if (go == true && mounted) {
        await _run(native.openAllFilesSettings);
      }
    }

    await ref.read(nativeStatusProvider.notifier).refresh();
    if (!mounted) return;
    if (!ref.read(nativeStatusProvider).batteryIgnored) {
      final go = await _confirm(
        title: '建议忽略电池优化',
        body: '小米等系统会在后台杀掉前台服务，挂载会掉。接下来打开系统页，请把本应用设为「无限制」或不优化。',
        action: '去设置',
      );
      if (go == true && mounted) {
        await _run(native.requestIgnoreBattery);
      }
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<String> Function() action) async {
    try {
      final message = await action();
      await ref.read(nativeStatusProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打不开系统页：$e')));
    }
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(nativeStatusProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _enterApp();
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('权限设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '首次使用需要下面两项系统权限。点卡片会打开对应设置页。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _PermissionCard(
            icon: Icons.folder_open,
            title: '所有文件访问权限',
            subtitle: status.hasAllFiles
                ? '已授予'
                : '挂载到手机目录、下载/上传公共目录都需要',
            granted: status.hasAllFiles,
            onTap: () => _run(ref.read(nativeBridgeProvider).openAllFilesSettings),
          ),
          _PermissionCard(
            icon: Icons.battery_saver_outlined,
            title: '忽略电池优化',
            subtitle: status.batteryIgnored
                ? '已忽略'
                : '避免小米省电策略杀掉挂载服务，请选「无限制」',
            granted: status.batteryIgnored,
            onTap: () => _run(ref.read(nativeBridgeProvider).requestIgnoreBattery),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('通知'),
            subtitle: const Text('前台服务保活需要通知权限'),
            trailing: TextButton(
              onPressed: () async {
                await Permission.notification.request();
              },
              child: const Text('申请'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('定位 / 附近的设备'),
            subtitle: const Text('用来读取当前 WiFi 名称，做自动挂载'),
            trailing: TextButton(
              onPressed: () async {
                await Permission.locationWhenInUse.request();
                await Permission.nearbyWifiDevices.request();
                await ref.read(nativeStatusProvider.notifier).refresh();
              },
              child: const Text('申请'),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _enterApp,
            child: Text(status.needsPermissionSetup ? '稍后进入应用' : '进入应用'),
          ),
        ],
      ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: granted ? scheme.primary : scheme.error),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.chevron_right),
        onTap: granted ? null : onTap,
      ),
    );
  }
}
