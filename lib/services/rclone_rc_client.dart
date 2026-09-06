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
    Map<String, dynamic> params,
  ) async {
    final started = await call(method, {...params, '_async': true});
    final jobId = started['jobid'] ?? started['jobId'];
    if (jobId == null) return started;
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
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
  }) async {
    await callAsync('operations/copyfile', {
      'srcFs': srcFs,
      'srcRemote': srcRemote,
      'dstFs': dstFs,
      'dstRemote': dstRemote,
    });
  }

  Future<Map<String, dynamic>> version() => call('core/version');
}
