import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/app_models.dart';
import '../providers/app_providers.dart';
import '../services/rclone_rc_client.dart';
import '../services/transfer_session.dart';

class FileManagerScreen extends ConsumerStatefulWidget {
  const FileManagerScreen({super.key});

  @override
  ConsumerState<FileManagerScreen> createState() => FileManagerScreenState();
}

class FileManagerScreenState extends ConsumerState<FileManagerScreen> {
  String? _remote;
  String _path = '';
  List<RemoteEntry> _entries = [];
  bool _loading = false;
  String? _error;
  String? _transferText;
  int? _transferPercent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(remotesProvider.notifier).reload();
    });
  }

  RcloneRcClient? get _client => ref.read(rcClientProvider);

  String get _fs {
    final remote = _remote;
    if (remote == null) return '';
    return _path.isEmpty ? '$remote:' : '$remote:$_path';
  }

  Future<void> _reload() async {
    final client = _client;
    if (client == null || _remote == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await client.listPath(_fs);
      items.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() => _entries = items);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(RemoteEntry entry) {
    if (!entry.isDir) return;
    setState(() {
      _path = _path.isEmpty ? entry.name : '$_path/${entry.name}';
    });
    _reload();
  }

  bool handleBack() {
    if (_remote == null && _path.isEmpty) return false;
    _up();
    return true;
  }

  void _up() {
    if (_path.isEmpty) {
      setState(() {
        _remote = null;
        _entries = [];
      });
      return;
    }
    final parts = _path.split('/')..removeLast();
    setState(() => _path = parts.join('/'));
    _reload();
  }

  Future<void> _mkdir() async {
    final name = await _prompt('新建文件夹', '名称');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _client?.mkdir('$_remote:', _join(name.trim()));
      await _reload();
    } catch (e) {
      _toast('创建失败：$e');
    }
  }

  Future<void> _delete(RemoteEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除 ${entry.name}？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TransferSession.run(
        native: ref.read(nativeBridgeProvider),
        title: '正在删除',
        name: entry.name,
        body: (report) async {
          _setTransfer('正在删除 ${entry.name}', null);
          report(text: '正在删除 ${entry.name}');
          if (entry.isDir) {
            await _client?.purge('$_remote:', _join(entry.name));
          } else {
            await _client?.delete('$_remote:', _join(entry.name));
          }
        },
      );
      await _reload();
    } catch (e) {
      _toast('删除失败：$e');
    } finally {
      _setTransfer(null, null);
    }
  }

  String _join(String name) => _path.isEmpty ? name : '$_path/$name';

  Future<void> _download(RemoteEntry entry) async {
    try {
      final native = ref.read(nativeBridgeProvider);
      final destDir = await native.defaultDownloadDir();
      await TransferSession.run(
        native: native,
        title: '正在下载',
        name: entry.name,
        body: (report) async {
          _setTransfer('正在下载 ${entry.name}', null);
          await _client?.copyFile(
            srcFs: '$_remote:',
            srcRemote: _join(entry.name),
            dstFs: destDir,
            dstRemote: entry.name,
            onJob: (jobId) => report(jobId: jobId),
            onProgress: (percent, text) {
              _setTransfer(text, percent);
              report(percent: percent, text: text);
            },
          );
        },
      );
      _toast('已下载到 $destDir/${entry.name}');
    } catch (e) {
      _toast('下载失败：$e');
    } finally {
      _setTransfer(null, null);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    try {
      String localFs;
      String localName = file.name;
      if (file.path != null && File(file.path!).existsSync()) {
        localFs = p.dirname(file.path!);
        localName = p.basename(file.path!);
      } else if (file.bytes != null) {
        final tmp = File('${Directory.systemTemp.path}/${file.name}');
        await tmp.writeAsBytes(file.bytes!);
        localFs = tmp.parent.path;
        localName = tmp.uri.pathSegments.last;
      } else {
        throw RcloneRcException('无法读取所选文件');
      }
      await TransferSession.run(
        native: ref.read(nativeBridgeProvider),
        title: '正在上传',
        name: localName,
        body: (report) async {
          _setTransfer('正在上传 $localName', null);
          await _client?.copyFile(
            srcFs: localFs,
            srcRemote: localName,
            dstFs: '$_remote:',
            dstRemote: _join(localName),
            onJob: (jobId) => report(jobId: jobId),
            onProgress: (percent, text) {
              _setTransfer(text, percent);
              report(percent: percent, text: text);
            },
          );
        },
      );
      _toast('已上传 $localName');
      await _reload();
    } catch (e) {
      _toast('上传失败：$e');
    } finally {
      _setTransfer(null, null);
    }
  }

  void _setTransfer(String? text, int? percent) {
    if (!mounted) return;
    setState(() {
      _transferText = text;
      _transferPercent = percent;
    });
  }

  Future<String?> _prompt(String title, String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(_remote == null ? '文件' : _fs),
        leading: _remote != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _up) : null,
        actions: [
          if (_remote != null) ...[
            IconButton(onPressed: _mkdir, icon: const Icon(Icons.create_new_folder_outlined)),
            IconButton(onPressed: _upload, icon: const Icon(Icons.upload_file)),
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_transferText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_transferText!, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _transferPercent == null
                        ? null
                        : (_transferPercent!.clamp(0, 100) / 100),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _remote == null
          ? remotes.isEmpty
              ? const Center(child: Text('还没有远程。请先添加网盘。'))
              : ListView(
                  children: remotes
                      .map(
                        (e) => ListTile(
                          leading: const Icon(Icons.cloud_outlined),
                          title: Text(e.name),
                          subtitle: Text(e.type),
                          onTap: () {
                            setState(() {
                              _remote = e.name;
                              _path = '';
                            });
                            _reload();
                          },
                        ),
                      )
                      .toList(),
                )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final size = entry.isDir
                              ? '文件夹'
                              : NumberFormat.compact().format(entry.size);
                          return ListTile(
                            leading: Icon(entry.isDir ? Icons.folder : Icons.insert_drive_file_outlined),
                            title: Text(entry.name),
                            subtitle: Text(size),
                            onTap: entry.isDir ? () => _open(entry) : null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'download' && !entry.isDir) _download(entry);
                                if (value == 'delete') _delete(entry);
                              },
                              itemBuilder: (context) => [
                                if (!entry.isDir)
                                  const PopupMenuItem(value: 'download', child: Text('下载到手机')),
                                const PopupMenuItem(value: 'delete', child: Text('删除')),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
