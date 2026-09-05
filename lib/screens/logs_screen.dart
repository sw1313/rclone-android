import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/app_providers.dart';

class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);
    final fmt = DateFormat('HH:mm:ss');
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            onPressed: () => ref.read(logsProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('暂无日志'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final item = logs[logs.length - 1 - index];
                final color = switch (item.level) {
                  'error' => Colors.red,
                  'warn' => Colors.orange,
                  'debug' => Colors.grey,
                  _ => null,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${fmt.format(item.time)} [${item.level}] ${item.message}',
                    style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 12),
                  ),
                );
              },
            ),
    );
  }
}
