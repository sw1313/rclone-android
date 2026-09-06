#!/system/bin/sh
# Magisk late_start：只后台拉服务，不打开界面
PKG=com.rcloneandroid.rclone_android
SVC=$PKG/.RcloneService
SETTINGS=/data/user/0/$PKG/files/settings.json
MODDIR=${0%/*}

n=0
while [ $n -lt 90 ]; do
  if [ -d /sdcard/Android ]; then
    break
  fi
  n=$((n + 1))
  sleep 2
done

n=0
while [ $n -lt 45 ]; do
  if pm list packages >/dev/null 2>&1; then
    break
  fi
  n=$((n + 1))
  sleep 2
done

# 应用已卸载：删掉本模块和旧的 service.d 脚本
if ! pm path "$PKG" >/dev/null 2>&1; then
  rm -rf /data/adb/modules/rclone-android
  rm -f /data/adb/service.d/rclone-android.sh
  exit 0
fi

if [ -f "$SETTINGS" ] && grep -Eq '"startOnBoot":[[:space:]]*false' "$SETTINGS"; then
  exit 0
fi

sleep 5
am start-foreground-service -n "$SVC" >/dev/null 2>&1
sleep 20
am start-foreground-service -n "$SVC" >/dev/null 2>&1
sleep 40
am start-foreground-service -n "$SVC" >/dev/null 2>&1
