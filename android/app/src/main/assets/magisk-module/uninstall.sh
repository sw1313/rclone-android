#!/system/bin/sh
# 用户在 Magisk 里删除本模块时执行
if [ -f /data/adb/modules/rclone-android/watchdog.pid ]; then
  kill -9 "$(cat /data/adb/modules/rclone-android/watchdog.pid)" 2>/dev/null || true
fi
pkill -f '/data/adb/modules/rclone-android/watchdog.sh' 2>/dev/null || true
pkill -f '/data/adb/modules/rclone-android/net.inotify' 2>/dev/null || true
pkill -f 'inotifyd /data/adb/modules/rclone-android/net.inotify' 2>/dev/null || true
rm -f /data/adb/service.d/rclone-android.sh
