import 'package:flutter_test/flutter_test.dart';
import 'package:rclone_android/models/app_models.dart';

void main() {
  test('MountProfile json roundtrip', () {
    const profile = MountProfile(
      id: '1',
      name: '网盘',
      remoteName: 'webdav',
      remotePath: 'Movies',
      localPath: '/storage/emulated/0/Cloud/webdav',
      enabled: true,
    );
    final again = MountProfile.fromJson(profile.toJson());
    expect(again.remoteSpec, 'webdav:Movies');
    expect(again.flags.vfsCacheMode, 'writes');
    expect(again.enabled, isTrue);
  });

  test('WifiRule json roundtrip', () {
    const rule = WifiRule(
      id: 'r1',
      ssid: 'Home',
      trigger: 'connect',
      action: 'mount',
      profileIds: ['1'],
    );
    final again = WifiRule.fromJson(rule.toJson());
    expect(again.ssid, 'Home');
    expect(again.profileIds, ['1']);
  });
}
