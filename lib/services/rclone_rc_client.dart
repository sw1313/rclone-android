import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class RcloneRcException implements Exception {
  RcloneRcException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RcloneRcClient {
  RcloneRcClient({
    required this.baseUrl,
    required this.user,
    required this.pass,
  });

  final String baseUrl;
  final String user;
  final String pass;

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String method) {
    final root = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse('$root$method');
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  ]) async {
    final response = await http
        .post(
          _uri(method),
          headers: _headers,
          body: jsonEncode(params ?? const <String, dynamic>{}),
        )
        .timeout(timeout);
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      } else if (decoded is Map) {
        body = decoded.cast<String, dynamic>();
      }
    }
    if (response.statusCode >= 400 || body['error'] != null) {
      throw RcloneRcException(
        (body['error'] ?? response.body).toString(),
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> callAsync(
    String method,
    Map<String, dynamic> params, {
    void Function(int? percent, String text)? onProgress,
    void Function(int jobId)? onJob,
  }) async {
    final started = await call(method, {...params, '_async': true});
    final rawId = started['jobid'] ?? started['jobId'];
    if (rawId == null) return started;
    final jobId = rawId is num ? rawId.toInt() : int.tryParse(rawId.toString());
    if (jobId != null) onJob?.call(jobId);
    final group = 'job/$jobId';
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (onProgress != null) {
        try {
          final progress = _progressFromStats(await call('core/stats', {'group': group}));
          onProgress(progress.$1, progress.$2);
        } catch (_) {}
      }
      final status = await call('job/status', {'jobid': jobId});
      if (status['finished'] == true) {
        if (status['success'] == false) {
          throw RcloneRcException((status['error'] ?? '任务失败').toString());
        }
        final output = status['output'];
        if (output is Map<String, dynamic>) return output;
        if (output is Map) return output.cast<String, dynamic>();
        return status;
      }
    }
    throw RcloneRcException('任务超时');
  }

  (int?, String) _progressFromStats(Map<String, dynamic> stats) {
    final transferring = stats['transferring'];
    if (transferring is List && transferring.isNotEmpty && transferring.first is Map) {
      final item = (transferring.first as Map).cast<String, dynamic>();
      final name = (item['name'] ?? '').toString();
      final pct = (item['percentage'] as num?)?.toInt();
      final bytes = _size(item['bytes']);
      final size = _size(item['size']);
      final text = [
        if (name.isNotEmpty) name,
        if (bytes != null && size != null) '$bytes / $size',
      ].join(' · ');
      return (pct, text.isEmpty ? '传输中' : text);
    }
    final bytes = (stats['bytes'] as num?)?.toInt() ?? 0;
    final total = (stats['totalBytes'] as num?)?.toInt() ?? 0;
    final pct = total > 0 ? ((bytes * 100) / total).round().clamp(0, 100) : null;
    final text = total > 0 ? '${_size(bytes)} / ${_size(total)}' : '处理中…';
    return (pct, text);
  }

  String? _size(Object? value) {
    final n = value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (n == null || n < 0) return null;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = n.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    final shown = size >= 10 || i == 0 ? size.round().toString() : size.toStringAsFixed(1);
    return '$shown ${units[i]}';
  }

  Future<List<RemoteInfo>> listRemotes() async {
    final dump = await call('config/dump');
    return dump.entries
        .where((e) => e.value is Map)
        .map((e) {
          final params = (e.value as Map).cast<String, dynamic>();
          return RemoteInfo(
            name: e.key,
            type: (params['type'] ?? 'unknown').toString(),
            params: params,
          );
        })
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> createRemote({
    required String name,
    required String type,
    required Map<String, String> parameters,
    bool obscure = true,
  }) async {
    await call('config/create', {
      'name': name,
      'type': type,
      'parameters': parameters,
      'opt': {'obscure': obscure},
    });
  }

  Future<void> updateRemote({
    required String name,
    required Map<String, String> parameters,
    bool obscure = true,
  }) async {
    await call('config/update', {
      'name': name,
      'parameters': parameters,
      'opt': {'obscure': obscure},
    });
  }

  Future<void> deleteRemote(String name) async {
    await call('config/delete', {'name': name});
  }

  /// 用当前表单参数临时建远程并列表，不依赖是否已保存。测完立刻删掉临时项。
  Future<int> probeRemote({
    required String type,
    required Map<String, String> parameters,
    bool obscure = true,
  }) async {
    final name = '__probe_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await createRemote(
        name: name,
        type: type,
        parameters: parameters,
        obscure: obscure,
      );
      final items = await listPath('$name:');
      return items.length;
    } finally {
      try {
        await deleteRemote(name);
      } catch (_) {}
    }
  }

  Future<String> versionLabel() async {
    final body = await call('core/version');
    final version = body['version']?.toString();
    final os = body['os']?.toString();
    final arch = body['arch']?.toString();
    if (version == null || version.isEmpty) return '';
    return [version, os, arch].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
  }

  Future<List<RemoteEntry>> listPath(String fs) async {
    final split = splitFs(fs);
    final remote = split.$2;
    final result = await call('operations/list', {
      'fs': split.$1,
      'remote': remote,
    }, const Duration(seconds: 45));
    final list = (result['list'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => RemoteEntry.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static (String, String) splitFs(String fs) {
    final idx = fs.indexOf(':');
    if (idx < 0) {
      return ('$fs:', '');
    }
    return ('${fs.substring(0, idx)}:', fs.substring(idx + 1));
  }

  Future<void> mkdir(String fs, String remote) async {
    await call('operations/mkdir', {'fs': fs, 'remote': remote});
  }

  Future<void> delete(String fs, String remote) async {
    await call('operations/delete', {'fs': fs, 'remote': remote});
  }

  Future<void> purge(String fs, String remote) async {
    await call('operations/purge', {'fs': fs, 'remote': remote});
  }

  Future<void> copyFile({
    required String srcFs,
    required String srcRemote,
    required String dstFs,
    required String dstRemote,
    void Function(int? percent, String text)? onProgress,
    void Function(int jobId)? onJob,
  }) async {
    await callAsync(
      'operations/copyfile',
      {
        'srcFs': srcFs,
        'srcRemote': srcRemote,
        'dstFs': dstFs,
        'dstRemote': dstRemote,
      },
      onProgress: onProgress,
      onJob: onJob,
    );
  }

  Future<Map<String, dynamic>> version() => call('core/version');
}
