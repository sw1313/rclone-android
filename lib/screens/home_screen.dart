import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../widgets/status_banner.dart';
import 'mount_edit_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mounts = ref.watch(mountsProvider);
    final status = ref.watch(nativeStatusProvider);
    final settings = ref.watch(settingsProvider);
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('挂载'),
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: () => ref.read(nativeStatusProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: remotes.isEmpty
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先在「远程」里添加网盘或导入 rclone.conf')),
                )
            : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MountEditScreen()),
                ),
        icon: const Icon(Icons.add),
        label: const Text('添加挂载'),
      ),
      body: Column(
        children: [
          const StatusBanner(),
          Expanded(
            child: mounts.isEmpty
                ? const Center(child: Text('还没有挂载配置。先添加远程，再创建挂载。'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    itemCount: mounts.length,
                    itemBuilder: (context, index) {
                      final profile = mounts[index];
                      final mounted = status.mountedIds.contains(profile.id);
                      final canMount = settings.preferRealMount && status.canRealMount;
                      final on = canMount ? mounted : profile.enabled;
                      return Card(
                        child: ListTile(
                          title: Text(profile.name),
                          subtitle: Text(
                            '${profile.remoteSpec}\n→ ${profile.localPath}'
                            '${mounted ? '\n已挂载' : ''}',
                          ),
                          isThreeLine: true,
                          leading: Icon(on ? Icons.cloud_done : Icons.cloud_off),
                          trailing: Switch(
                            value: on,
                            onChanged: (value) async {
                              try {
                                if (value && !canMount) {
                                  await ref.read(mountsProvider.notifier).setEnabled(profile.id, true);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('无 Root 或未开启真实挂载，已仅标记启用。请用「文件」页访问。'),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                await ref.read(mountsProvider.notifier).toggleMount(profile, value);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('操作失败：$e')),
                                  );
                                }
                              }
                            },
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MountEditScreen(existing: profile),
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
