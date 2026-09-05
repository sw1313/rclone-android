import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'remote_edit_screen.dart';

class RemotesScreen extends ConsumerWidget {
  const RemotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remotes = ref.watch(remotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('远程'),
        actions: [
          IconButton(
            tooltip: '导入 rclone.conf',
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: '导出 rclone.conf',
            onPressed: () => _export(context, ref),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            onPressed: () => ref.read(remotesProvider.notifier).reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const RemoteEditScreen()),
          );
          await ref.read(remotesProvider.notifier).reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('添加远程'),
      ),
      body: remotes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('还没有远程。可添加 WebDAV/SFTP，或导入电脑上的 rclone.conf。'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final remote = items[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(remote.name),
                  subtitle: Text(remote.type),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('删除远程'),
                          content: Text('确定删除 ${remote.name}？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref.read(remotesProvider.notifier).delete(remote.name);
                      }
                    },
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RemoteEditScreen(
                          existingName: remote.name,
                          existingType: remote.type,
                        ),
                      ),
                    );
                    await ref.read(remotesProvider.notifier).reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    String? text;
    if (file.bytes != null) {
      text = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      text = await File(file.path!).readAsString();
    }
    if (text == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法读取所选文件')));
      }
      return;
    }
    await ref.read(nativeBridgeProvider).writeConfig(text);
    await ref.read(nativeStatusProvider.notifier).refresh();
    await ref.read(remotesProvider.notifier).reload();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已导入 rclone.conf 并重启服务')));
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final content = await ref.read(nativeBridgeProvider).readConfig();
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: '导出 rclone.conf',
      fileName: 'rclone.conf',
      bytes: utf8.encode(content),
    );
    if (!context.mounted) return;
    if (saved == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('rclone.conf'),
          content: SingleChildScrollView(
            child: SelectableText(content.isEmpty ? '（空）' : content),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出')));
  }
}
