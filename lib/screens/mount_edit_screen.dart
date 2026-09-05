import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../providers/app_providers.dart';

class MountEditScreen extends ConsumerStatefulWidget {
  const MountEditScreen({super.key, this.existing});

  final MountProfile? existing;

  @override
  ConsumerState<MountEditScreen> createState() => _MountEditScreenState();
}

class _MountEditScreenState extends ConsumerState<MountEditScreen> {
  final _name = TextEditingController();
  final _remotePath = TextEditingController();
  final _localPath = TextEditingController();
  final _vfsCacheMaxSize = TextEditingController();
  final _vfsCacheMaxAge = TextEditingController();
  final _dirCacheTime = TextEditingController();
  final _bufferSize = TextEditingController();
  final _chunkSize = TextEditingController();
  final _transfers = TextEditingController();
  final _checkers = TextEditingController();
  final _bwlimit = TextEditingController();
  final _uid = TextEditingController();
  final _gid = TextEditingController();
  final _umask = TextEditingController();
  final _dirPerms = TextEditingController();
  final _filePerms = TextEditingController();
  final _extraArgs = TextEditingController();
  String? _remoteName;
  String _vfsCacheMode = 'writes';
  String _logLevel = 'INFO';
  bool _allowOther = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final flags = existing?.flags ?? const RcloneMountFlags();
    _name.text = existing?.name ?? '';
    _remoteName = existing?.remoteName;
    _remotePath.text = existing?.remotePath ?? '';
    _localPath.text = existing?.localPath ?? '/storage/emulated/0/Cloud/';
    _vfsCacheMode = flags.vfsCacheMode;
    _vfsCacheMaxSize.text = flags.vfsCacheMaxSize;
    _vfsCacheMaxAge.text = flags.vfsCacheMaxAge;
    _dirCacheTime.text = flags.dirCacheTime;
    _bufferSize.text = flags.bufferSize;
    _chunkSize.text = flags.vfsReadChunkSize;
    _transfers.text = flags.transfers.toString();
    _checkers.text = flags.checkers.toString();
    _bwlimit.text = flags.bwlimit;
    _uid.text = flags.uid;
    _gid.text = flags.gid;
    _umask.text = flags.umask;
    _dirPerms.text = flags.dirPerms;
    _filePerms.text = flags.filePerms;
    _allowOther = flags.allowOther;
    _logLevel = flags.logLevel;
    _extraArgs.text = flags.extraArgs;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _remotePath,
      _localPath,
      _vfsCacheMaxSize,
      _vfsCacheMaxAge,
      _dirCacheTime,
      _bufferSize,
      _chunkSize,
      _transfers,
      _checkers,
      _bwlimit,
      _uid,
      _gid,
      _umask,
      _dirPerms,
      _filePerms,
      _extraArgs,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final remotes = ref.read(remotesProvider).valueOrNull ?? const [];
    final remoteName = _remoteName ?? (remotes.isNotEmpty ? remotes.first.name : '');
    if (remoteName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择远程')));
      return;
    }
    final name = _name.text.trim().isEmpty ? remoteName : _name.text.trim();
    var local = _localPath.text.trim();
    if (local.isEmpty) {
      local = '/storage/emulated/0/Cloud/$name';
    }
    final flags = RcloneMountFlags(
      vfsCacheMode: _vfsCacheMode,
      vfsCacheMaxSize: _vfsCacheMaxSize.text.trim(),
      vfsCacheMaxAge: _vfsCacheMaxAge.text.trim(),
      dirCacheTime: _dirCacheTime.text.trim(),
      bufferSize: _bufferSize.text.trim(),
      vfsReadChunkSize: _chunkSize.text.trim(),
      transfers: int.tryParse(_transfers.text.trim()) ?? 4,
      checkers: int.tryParse(_checkers.text.trim()) ?? 8,
      bwlimit: _bwlimit.text.trim(),
      uid: _uid.text.trim(),
      gid: _gid.text.trim(),
      umask: _umask.text.trim(),
      dirPerms: _dirPerms.text.trim(),
      filePerms: _filePerms.text.trim(),
      allowOther: _allowOther,
      logLevel: _logLevel,
      extraArgs: _extraArgs.text.trim(),
    );
    final profile = MountProfile(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      remoteName: remoteName,
      remotePath: _remotePath.text.trim(),
      localPath: local,
      enabled: widget.existing?.enabled ?? false,
      flags: flags,
    );
    setState(() => _saving = true);
    try {
      await ref.read(mountsProvider.notifier).upsert(profile);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remotes = ref.watch(remotesProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '添加挂载' : '编辑挂载'),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(mountsProvider.notifier).remove(widget.existing!.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: '显示名称', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: remotes.any((e) => e.name == _remoteName) ? _remoteName : null,
            items: remotes
                .map((e) => DropdownMenuItem(value: e.name, child: Text('${e.name} (${e.type})')))
                .toList(),
            onChanged: (value) {
              setState(() {
                _remoteName = value;
                if (_localPath.text.endsWith('/Cloud/') || _localPath.text == '/storage/emulated/0/Cloud/') {
                  _localPath.text = '/storage/emulated/0/Cloud/$value';
                }
              });
            },
            decoration: const InputDecoration(labelText: '远程', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remotePath,
            decoration: const InputDecoration(
              labelText: '远程子路径（可空）',
              hintText: '例如 Movies',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _localPath,
            decoration: const InputDecoration(
              labelText: '手机挂载路径',
              hintText: '/storage/emulated/0/Cloud/xxx',
              border: OutlineInputBorder(),
              helperText: 'Root 下会 bind 到 /mnt/runtime/*/emulated/0/… 供其他 App 访问',
            ),
          ),
          const SizedBox(height: 24),
          Text('常用 rclone 参数', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _vfsCacheMode,
            items: const [
              DropdownMenuItem(value: 'off', child: Text('off')),
              DropdownMenuItem(value: 'minimal', child: Text('minimal')),
              DropdownMenuItem(value: 'writes', child: Text('writes（推荐）')),
              DropdownMenuItem(value: 'full', child: Text('full')),
            ],
            onChanged: (v) => setState(() => _vfsCacheMode = v ?? 'writes'),
            decoration: const InputDecoration(labelText: '--vfs-cache-mode', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          _field(_vfsCacheMaxSize, '--vfs-cache-max-size'),
          _field(_vfsCacheMaxAge, '--vfs-cache-max-age'),
          _field(_dirCacheTime, '--dir-cache-time'),
          _field(_bufferSize, '--buffer-size'),
          _field(_chunkSize, '--vfs-read-chunk-size'),
          _field(_transfers, '--transfers'),
          _field(_checkers, '--checkers'),
          _field(_bwlimit, '--bwlimit（可空）'),
          _field(_uid, '--uid（可空）'),
          _field(_gid, '--gid'),
          _field(_umask, '--umask'),
          _field(_dirPerms, '--dir-perms'),
          _field(_filePerms, '--file-perms'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('--allow-other'),
            value: _allowOther,
            onChanged: (v) => setState(() => _allowOther = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: _logLevel,
            items: const ['ERROR', 'NOTICE', 'INFO', 'DEBUG']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _logLevel = v ?? 'INFO'),
            decoration: const InputDecoration(labelText: '--log-level', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extraArgs,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '额外参数（按空格拆分，支持引号）',
              hintText: '--vfs-read-ahead 128M',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}
