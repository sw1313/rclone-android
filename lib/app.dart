import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/app_models.dart';
import 'providers/app_providers.dart';
import 'screens/app_shell.dart';
import 'screens/permission_setup_page.dart';

class RcloneApp extends StatelessWidget {
  const RcloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      title: 'rclone 挂载',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
      ),
      home: const BootstrapPage(),
    );
  }
}

class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  String _step = '正在准备 rclone…';
  String? _error;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_boot);
  }

  Future<void> _boot() async {
    final native = ref.read(nativeBridgeProvider);
    try {
      native.events().listen((event) {
        if (!mounted) return;
        ref.read(nativeStatusProvider.notifier).applyEvent(event);
        if (event['type'] == 'log') {
          ref.read(logsProvider.notifier).add(
                LogItem(
                  time: DateTime.fromMillisecondsSinceEpoch(
                    (event['time'] as num?)?.toInt() ??
                        DateTime.now().millisecondsSinceEpoch,
                  ),
                  level: (event['level'] ?? 'info').toString(),
                  message: (event['message'] ?? '').toString(),
                ),
              );
        }
      });

      setState(() => _step = '释放二进制…');
      await native.prepareBinaries();
      setState(() => _step = '启动前台服务…');
      await native.startService();
      await Permission.notification.request();
      await Permission.locationWhenInUse.request();
      await Permission.nearbyWifiDevices.request();
      setState(() => _step = '启动 rclone 服务…');
      await native.startRcd();
      await native.startWifiMonitor();
      setState(() => _step = '读取配置…');
      await ref.read(settingsProvider.notifier).load();
      await ref.read(mountsProvider.notifier).load();
      await ref.read(wifiRulesProvider.notifier).load();
      await ref.read(nativeStatusProvider.notifier).refresh();
      await ref.read(remotesProvider.notifier).reload();
      if (!mounted) return;
      final status = ref.read(nativeStatusProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => status.needsPermissionSetup
              ? const PermissionSetupPage()
              : const AppShell(),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_sync, size: 64),
              const SizedBox(height: 16),
              Text('rclone 挂载', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              if (_error == null) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_error == null ? _step : _error!, textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: _boot, child: const Text('重试')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
