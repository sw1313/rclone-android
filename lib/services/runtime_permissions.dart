import 'package:permission_handler/permission_handler.dart';

class RuntimePermissions {
  static Future<bool> isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  static Future<bool> notificationOk() => isGranted(Permission.notification);

  static Future<bool> locationOk() async {
    return await isGranted(Permission.locationWhenInUse) ||
        await isGranted(Permission.location) ||
        await isGranted(Permission.nearbyWifiDevices);
  }

  static Future<void> requestMissing() async {
    if (!await notificationOk()) {
      await Permission.notification.request();
    }
    if (!await isGranted(Permission.locationWhenInUse) &&
        !await isGranted(Permission.location)) {
      await Permission.locationWhenInUse.request();
    }
    if (!await locationOk()) {
      await Permission.nearbyWifiDevices.request();
    }
  }
}
