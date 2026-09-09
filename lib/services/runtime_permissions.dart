import 'package:permission_handler/permission_handler.dart';

class RuntimePermissions {
  static Future<bool> isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  static Future<bool> notificationOk() => isGranted(Permission.notification);

  static Future<void> requestNotification() async {
    if (!await notificationOk()) {
      await Permission.notification.request();
    }
  }
}
