import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../services/native_bridge.dart';
import '../services/rclone_rc_client.dart';

final nativeBridgeProvider = Provider<NativeBridge>((ref) => NativeBridge());

final nativeStatusProvider =
    NotifierProvider<NativeStatusNotifier, NativeStatus>(NativeStatusNotifier.new);

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final mountsProvider =
    NotifierProvider<MountsNotifier, List<MountProfile>>(MountsNotifier.new);

final remotesProvider =
    AsyncNotifierProvider<RemotesNotifier, List<RemoteInfo>>(RemotesNotifier.new);

final wifiRulesProvider =
    NotifierProvider<WifiRulesNotifier, List<WifiRule>>(WifiRulesNotifier.new);

final logsProvider = NotifierProvider<LogsNotifier, List<LogItem>>(LogsNotifier.new);

final rcClientProvider = Provider<RcloneRcClient?>((ref) {
  final status = ref.watch(nativeStatusProvider);
  if (!status.rcdRunning || status.rcdPass.isEmpty) return null;
  return RcloneRcClient(
    baseUrl: status.rcdUrl,
    user: status.rcdUser,
    pass: status.rcdPass,
  );
});

class NativeStatusNotifier extends Notifier<NativeStatus> {
  @override
  NativeStatus build() => const NativeStatus();

  Future<void> refresh() async {
    state = await ref.read(nativeBridgeProvider).getStatus();
    await ref.read(mountsProvider.notifier).syncEnabledWith(state.mountedIds);
  }

  void applyEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'daemon':
        state = state.copyWith(rcdRunning: event['running'] == true);
      case 'mount':
        final id = event['id']?.toString();
        if (id == null) return;
        final ids = [...state.mountedIds];
        if (event['mounted'] == true) {
          if (!ids.contains(id)) ids.add(id);
        } else {
          ids.remove(id);
        }
        state = state.copyWith(mountedIds: ids);
        unawaited(ref.read(mountsProvider.notifier).syncEnabledWith(ids));
      case 'wifi':
        if (event['event'] == 'connect') {
          state = state.copyWith(currentSsid: event['ssid']?.toString());
        } else if (event['event'] == 'disconnect') {
          state = state.copyWith(currentSsid: null);
        }
      case 'vpn':
        if (event['event'] == 'connect') {
          state = state.copyWith(currentVpn: event['vpn']?.toString());
        } else if (event['event'] == 'disconnect') {
          state = state.copyWith(currentVpn: null);
        }
    }
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings();

  Future<void> load() async {
    final raw = await ref.read(nativeBridgeProvider).readFile('settings.json', fallback: '{}');
    state = AppSettings.decode(raw);
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(nativeBridgeProvider).writeFile(
          'settings.json',
          const JsonEncoder.withIndent('  ').convert(next.toJson()),
        );
  }
}

class MountsNotifier extends Notifier<List<MountProfile>> {
  @override
  List<MountProfile> build() => const [];

  Future<void> load() async {
    final raw = await ref.read(nativeBridgeProvider).readFile('mounts.json', fallback: '[]');
    state = decodeMounts(raw);
  }

  Future<void> _persist() async {
    await ref.read(nativeBridgeProvider).writeFile(
          'mounts.json',
          const JsonEncoder.withIndent('  ').convert(state.map((e) => e.toJson()).toList()),
        );
  }

  Future<void> upsert(MountProfile profile) async {
    final next = [...state];
    final index = next.indexWhere((e) => e.id == profile.id);
    if (index >= 0) {
      next[index] = profile;
    } else {
      next.add(profile);
    }
    state = next;
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(enabled: enabled) else item,
    ];
    await _persist();
  }

  Future<void> syncEnabledWith(List<String> mountedIds) async {
    if (state.isEmpty) return;
    final live = mountedIds.toSet();
    var changed = false;
    final next = [
      for (final item in state)
        if (item.enabled != live.contains(item.id))
          item.copyWith(enabled: live.contains(item.id))
        else
          item,
    ];
    for (var i = 0; i < state.length; i++) {
      if (state[i].enabled != next[i].enabled) {
        changed = true;
        break;
      }
    }
    if (!changed) return;
    state = next;
    await _persist();
  }

  Future<void> toggleMount(MountProfile profile, bool on) async {
    final native = ref.read(nativeBridgeProvider);
    final status = await native.getStatus();
    final settings = ref.read(settingsProvider);
    final actuallyMounted = status.mountedIds.contains(profile.id);
    if (on) {
      if (settings.preferRealMount && status.canRealMount && !actuallyMounted) {
        await native.mount(profile.copyWith(enabled: true));
      }
      await setEnabled(profile.id, true);
      await ref.read(nativeStatusProvider.notifier).refresh();
      return;
    }
    try {
      await native.unmount(profile.id);
    } finally {
      await setEnabled(profile.id, false);
      await ref.read(nativeStatusProvider.notifier).refresh();
    }
  }
}

class RemotesNotifier extends AsyncNotifier<List<RemoteInfo>> {
  @override
  Future<List<RemoteInfo>> build() async => const [];

  Future<void> reload() async {
    final client = ref.read(rcClientProvider);
    if (client == null) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(client.listRemotes);
  }

  Future<void> create({
    required String name,
    required String type,
    required Map<String, String> parameters,
    bool obscure = true,
    bool update = false,
  }) async {
    final client = ref.read(rcClientProvider);
    if (client == null) {
      throw RcloneRcException('rclone 服务尚未就绪');
    }
    if (update) {
      await client.updateRemote(name: name, parameters: parameters, obscure: obscure);
    } else {
      await client.createRemote(
        name: name,
        type: type,
        parameters: parameters,
        obscure: obscure,
      );
    }
    await reload();
  }

  Future<void> delete(String name) async {
    final client = ref.read(rcClientProvider);
    if (client == null) return;
    await client.deleteRemote(name);
    await reload();
  }
}

class WifiRulesNotifier extends Notifier<List<WifiRule>> {
  @override
  List<WifiRule> build() => const [];

  Future<void> load() async {
    final raw = await ref.read(nativeBridgeProvider).readFile('wifi_rules.json', fallback: '[]');
    state = decodeWifiRules(raw);
  }

  Future<void> _persist() async {
    await ref.read(nativeBridgeProvider).writeFile(
          'wifi_rules.json',
          const JsonEncoder.withIndent('  ').convert(state.map((e) => e.toJson()).toList()),
        );
  }

  Future<void> upsert(WifiRule rule) async {
    final next = [...state];
    final index = next.indexWhere((e) => e.id == rule.id);
    if (index >= 0) {
      next[index] = rule;
    } else {
      next.add(rule);
    }
    state = next;
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }
}

class LogsNotifier extends Notifier<List<LogItem>> {
  @override
  List<LogItem> build() => const [];

  void add(LogItem item) {
    final next = [...state, item];
    if (next.length > 400) {
      state = next.sublist(next.length - 400);
    } else {
      state = next;
    }
  }

  void clear() => state = const [];
}
