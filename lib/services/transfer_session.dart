import 'native_bridge.dart';
import 'runtime_permissions.dart';

typedef TransferReporter = void Function({int? percent, String? text, int? jobId});

class TransferSession {
  TransferSession._();

  static int _seq = 0;

  static Future<T> run<T>({
    required NativeBridge native,
    required String title,
    required String name,
    required Future<T> Function(TransferReporter report) body,
  }) async {
    await RuntimePermissions.requestNotification();
    final id = 't${++_seq}';
    await native.beginTransfer(id: id, title: title, text: name);
    try {
      final result = await body(({percent, text, jobId}) {
        native.updateTransfer(
          id: id,
          text: text,
          progress: percent,
          jobId: jobId,
        );
      });
      await native.endTransfer(id: id, success: true, text: '已完成 $name');
      return result;
    } catch (e) {
      await native.endTransfer(id: id, success: false, text: '失败：$name');
      rethrow;
    }
  }
}
