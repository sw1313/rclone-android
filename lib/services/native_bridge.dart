import 'package:flutter/services.dart';

import '../models/app_models.dart';

class NativeBridge {
  NativeBridge();

  static const _channel = MethodChannel('com.rcloneandroid.rclone_android/native');
  static const _events = EventChannel('com.rcloneandroid.rclone_android/events');

  Stream<Map<String, dynamic>> events() {
    return _events.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return event.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{'type': 'unknown', 'raw': event};
    });
  }

  Future<NativeStatus> getStatus() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
    return NativeStatus.fromMap(raw ?? const {});
  }

  Future<void> prepareBinaries() async {
    await _channel.invokeMethod('prepareBinaries');
  }

  Future<void> startService() async {
    await _channel.invokeMethod('startService');
  }

  Future<NativeStatus> startRcd() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('startRcd');
    return NativeStatus.fromMap(raw ?? const {});
  }

  Future<void> stopRcd() async {
    await _channel.invokeMethod('stopRcd');
  }

  Future<bool> requestRoot() async {
    return await _channel.invokeMethod<bool>('requestRoot') ?? false;
  }

  Future<void> mount(MountProfile profile) async {
    await _channel.invokeMethod('mount', {'profile': profile.toJson()});
  }

  Future<void> unmount(String id) async {
    await _channel.invokeMethod('unmount', {'id': id});
  }

  Future<void> unmountAll() async {
    await _channel.invokeMethod('unmountAll');
  }

  Future<List<String>> listMountedIds() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listMounted');
    return (raw ?? const [])
        .map((e) {
          if (e is Map && e['id'] != null) return e['id'].toString();
          return e.toString();
        })
        .toList();
  }

  Future<String?> getCurrentSsid() {
    return _channel.invokeMethod<String>('getCurrentSsid');
  }

  Future<String?> getCurrentVpn() {
    return _channel.invokeMethod<String>('getCurrentVpn');
  }

  Future<void> startWifiMonitor() async {
    await _channel.invokeMethod('startWifiMonitor');
  }

  Future<String> requestIgnoreBattery() async {
    return _launchMessage(await _channel.invokeMethod('requestIgnoreBattery'));
  }

  Future<String> openAllFilesSettings() async {
    return _launchMessage(await _channel.invokeMethod('openAllFilesSettings'));
  }

  Future<String> openAppSettings() async {
    return _launchMessage(await _channel.invokeMethod('openAppSettings'));
  }

  String _launchMessage(dynamic raw) {
    if (raw is Map) {
      return (raw['message'] ?? '已打开系统页').toString();
    }
    return '已打开系统页';
  }

  Future<String> readFile(String name, {String fallback = ''}) async {
    return await _channel.invokeMethod<String>(
          'readFile',
          {'name': name, 'fallback': fallback},
        ) ??
        fallback;
  }

  Future<void> writeFile(String name, String content) async {
    await _channel.invokeMethod('writeFile', {'name': name, 'content': content});
  }

  Future<String> readConfig() async {
    return await _channel.invokeMethod<String>('readConfig') ?? '';
  }

  Future<void> writeConfig(String content) async {
    await _channel.invokeMethod('writeConfig', {'content': content});
  }

  Future<String> defaultDownloadDir() async {
    return await _channel.invokeMethod<String>('defaultDownloadDir') ??
        '/storage/emulated/0/Download';
  }
}
