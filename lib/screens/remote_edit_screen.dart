import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class RemoteKind {
  const RemoteKind(this.id, this.label, this.rcloneType);
  final String id;
  final String label;
  final String rcloneType;
}

const remoteKinds = [
  RemoteKind('webdav', 'WebDAV', 'webdav'),
  RemoteKind('sftp', 'SFTP', 'sftp'),
  RemoteKind('ftp', 'FTP', 'ftp'),
  RemoteKind('s3', 'S3 兼容', 's3'),
  RemoteKind('alias', 'Alias', 'alias'),
  RemoteKind('drive', 'Google Drive（Token）', 'drive'),
  RemoteKind('onedrive', 'OneDrive（Token）', 'onedrive'),
  RemoteKind('dropbox', 'Dropbox（Token）', 'dropbox'),
  RemoteKind('advanced', '高级 / 任意类型', ''),
];

class RemoteEditScreen extends ConsumerStatefulWidget {
  const RemoteEditScreen({super.key, this.existingName, this.existingType});

  final String? existingName;
  final String? existingType;

  @override
  ConsumerState<RemoteEditScreen> createState() => _RemoteEditScreenState();
}

class _RemoteEditScreenState extends ConsumerState<RemoteEditScreen> {
  final _name = TextEditingController();
  final _fields = <String, TextEditingController>{};
  String _kind = 'webdav';
  String _vendor = 'other';
  String _s3Provider = 'Other';
  bool _obscure = true;
  bool _saving = false;

  TextEditingController _c(String key, [String initial = '']) {
    return _fields.putIfAbsent(key, () => TextEditingController(text: initial));
  }

  @override
  void initState() {
    super.initState();
    _name.text = widget.existingName ?? '';
    final type = widget.existingType;
    if (type != null) {
      _kind = remoteKinds.any((e) => e.rcloneType == type) ? type : 'advanced';
      if (_kind == 'advanced') {
        _c('type', type);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String normalizeWebdavUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(url)) {
      url = 'http://$url';
    }
    return url;
  }

  Future<void> _test() async {
    final client = ref.read(rcClientProvider);
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('rclone 服务尚未就绪')));
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写远程名称并保存，再测试')));
      return;
    }
    setState(() => _saving = true);
    try {
      final items = await client.listPath('$name:');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接成功，列出 ${items.length} 项')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, String> _parameters() {
    switch (_kind) {
      case 'webdav':
        return {
          'url': normalizeWebdavUrl(_c('url').text),
          'vendor': _vendor,
          'user': _c('user').text.trim(),
          'pass': _c('pass').text,
        };
      case 'sftp':
        final map = {
          'host': _c('host').text.trim(),
          'port': _c('port', '22').text.trim(),
          'user': _c('user').text.trim(),
          'pass': _c('pass').text,
        };
        if (_c('key_file').text.trim().isNotEmpty) {
          map['key_file'] = _c('key_file').text.trim();
        }
        return map;
      case 'ftp':
        return {
          'host': _c('host').text.trim(),
          'port': _c('port', '21').text.trim(),
          'user': _c('user').text.trim(),
          'pass': _c('pass').text,
        };
      case 's3':
        return {
          'provider': _s3Provider,
          'access_key_id': _c('access_key_id').text.trim(),
          'secret_access_key': _c('secret_access_key').text,
          'endpoint': _c('endpoint').text.trim(),
          'region': _c('region').text.trim(),
          'acl': 'private',
        }..removeWhere((key, value) => value.isEmpty && key != 'secret_access_key');
      case 'alias':
        return {'remote': _c('remote').text.trim()};
      case 'drive':
      case 'onedrive':
      case 'dropbox':
        return {
          if (_c('token').text.trim().isNotEmpty) 'token': _c('token').text.trim(),
          if (_c('client_id').text.trim().isNotEmpty) 'client_id': _c('client_id').text.trim(),
          if (_c('client_secret').text.trim().isNotEmpty) 'client_secret': _c('client_secret').text.trim(),
        };
      default:
        final type = _c('type').text.trim();
        final raw = _c('kv').text;
        final params = <String, String>{};
        if (type.isNotEmpty) {
          // type is passed separately
        }
        for (final line in raw.split('\n')) {
          final idx = line.indexOf('=');
          if (idx <= 0) continue;
          params[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
        }
        return params;
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写远程名称')));
      return;
    }
    final kind = remoteKinds.firstWhere((e) => e.id == _kind);
    final type = _kind == 'advanced' ? _c('type').text.trim() : kind.rcloneType;
    if (type.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写 rclone 类型')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(remotesProvider.notifier).create(
            name: name,
            type: type,
            parameters: _parameters()..removeWhere((key, value) => value.isEmpty),
            obscure: _obscure,
            update: widget.existingName != null,
          );
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.existingName == null ? '添加远程' : '编辑远程')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            enabled: widget.existingName == null,
            decoration: const InputDecoration(labelText: '远程名称', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            items: remoteKinds
                .map((e) => DropdownMenuItem(value: e.id, child: Text(e.label)))
                .toList(),
            onChanged: (v) => setState(() => _kind = v ?? 'webdav'),
            decoration: const InputDecoration(labelText: '类型', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          ..._kindFields(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('密码字段自动 obscure'),
            value: _obscure,
            onChanged: (v) => setState(() => _obscure = v),
          ),
          if (_kind == 'drive' || _kind == 'onedrive' || _kind == 'dropbox')
            const Text('第一版不内置 OAuth。可在电脑执行 rclone authorize 后把 token JSON 粘贴到这里，或直接导入 rclone.conf。'),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _saving ? null : _test,
            child: const Text('测试连接'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  List<Widget> _kindFields() {
    switch (_kind) {
      case 'webdav':
        return [
          _box('url', 'WebDAV URL', hint: 'http://192.168.1.8:5244/dav'),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '局域网 HTTP 根地址可以写，例如 http://192.168.50.238:5055/ 。'
              '若网页能开、WebDAV 连不上，多半是服务挂在 /dav 或 /webdav，请把路径补上。',
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _vendor,
            items: const ['other', 'nextcloud', 'owncloud', 'sharepoint']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _vendor = v ?? 'other'),
            decoration: const InputDecoration(labelText: 'vendor', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          _box('user', '用户名'),
          _box('pass', '密码', obscure: true),
        ];
      case 'sftp':
        return [
          _box('host', '主机'),
          _box('port', '端口', initial: '22'),
          _box('user', '用户名'),
          _box('pass', '密码', obscure: true),
          _box('key_file', '私钥路径（可选）'),
        ];
      case 'ftp':
        return [
          _box('host', '主机'),
          _box('port', '端口', initial: '21'),
          _box('user', '用户名'),
          _box('pass', '密码', obscure: true),
        ];
      case 's3':
        return [
          DropdownButtonFormField<String>(
            initialValue: _s3Provider,
            items: const ['Other', 'AWS', 'Minio', 'Cloudflare', 'Alibaba', 'B2', 'Wasabi']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _s3Provider = v ?? 'Other'),
            decoration: const InputDecoration(labelText: 'provider', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          _box('access_key_id', 'Access Key'),
          _box('secret_access_key', 'Secret Key', obscure: true),
          _box('endpoint', 'Endpoint'),
          _box('region', 'Region（可空）'),
        ];
      case 'alias':
        return [_box('remote', '指向的 remote:path', hint: 'webdav:folder')];
      case 'drive':
      case 'onedrive':
      case 'dropbox':
        return [
          _box('token', 'token JSON', maxLines: 5),
          _box('client_id', 'client_id（可选）'),
          _box('client_secret', 'client_secret（可选）'),
        ];
      default:
        return [
          _box('type', 'rclone type', hint: 'webdav / drive / ...'),
          _box('kv', '参数（每行 key=value）', maxLines: 8),
        ];
    }
  }

  Widget _box(String key, String label, {String hint = '', bool obscure = false, int maxLines = 1, String initial = ''}) {
    final controller = _c(key, initial);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint.isEmpty ? null : hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
