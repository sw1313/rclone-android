import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class StatusBanner extends ConsumerWidget {
  const StatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(nativeStatusProvider);
    final settings = ref.watch(settingsProvider);
    final canMount = settings.preferRealMount && status.canRealMount;
    final scheme = Theme.of(context).colorScheme;
    final missing = <String>[
      if (!status.hasAllFiles) '所有文件访问',
      if (!status.batteryIgnored) '忽略电池优化',
    ];
    final text = missing.isNotEmpty
        ? '还缺权限：${missing.join('、')}。可到「设置」里授予。'
        : canMount
            ? '真实挂载可用（Root）。WiFi：${status.currentSsid ?? '未连接'}'
                '${status.currentVpn == null ? '' : ' · VPN：${status.currentVpn}'}'
            : status.rootAvailable
                ? '已有 Root，但当前为文件管理器模式或 fusermount 缺失'
                : '无 Root：可浏览/上传/下载，无法把网盘挂成系统目录';
    return Material(
      color: missing.isNotEmpty
          ? scheme.errorContainer
          : canMount
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              missing.isNotEmpty
                  ? Icons.privacy_tip_outlined
                  : canMount
                      ? Icons.verified_user
                      : Icons.info_outline,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
