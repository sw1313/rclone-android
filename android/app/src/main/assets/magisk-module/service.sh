#!/system/bin/sh
# Magisk late_start：看门狗负责挂载；可选再拉 App 前台服务做通知。
PKG=com.rcloneandroid.rclone_android
SVC=$PKG/.RcloneService
MODDIR=${0%/*}
SETTINGS=/data/user/0/$PKG/files/settings.json
BOOTPREF=/data/user_de/0/$PKG/files/boot_prefs.json

start_watchdog() {
  if [ -f "$MODDIR/watchdog.pid" ]; then
    old=$(cat "$MODDIR/watchdog.pid" 2>/dev/null)
    if [ -n "$old" ] && [ -d "/proc/$old" ]; then
      cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null)
      case "$cmd" in
        *watchdog.sh*) return 0 ;;
      esac
    fi
  fi
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$MODDIR/watchdog.sh" loop </dev/null >/dev/null 2>&1 &
  else
    nohup sh "$MODDIR/watchdog.sh" loop >/dev/null 2>&1 &
  fi
}

restart_watchdog_if_script_changed() {
  hash=$(md5sum "$MODDIR/watchdog.sh" "$MODDIR/common.sh" "$MODDIR/net.inotify" 2>/dev/null | md5sum | awk '{print $1}')
  old=$(cat "$MODDIR/.script_hash" 2>/dev/null || true)
  if [ -n "$hash" ] && [ "$hash" = "$old" ]; then
    start_watchdog
    return 0
  fi
  if [ -f "$MODDIR/watchdog.pid" ]; then
    kill -9 "$(cat "$MODDIR/watchdog.pid")" 2>/dev/null || true
  fi
  pkill -f 'inotifyd /data/adb/modules/rclone-android/net.inotify' 2>/dev/null || true
  # 只杀 loop，不要误杀正在执行的 tick（同脚本名）
  [ -n "$hash" ] && echo "$hash" > "$MODDIR/.script_hash"
  rm -f "$MODDIR/watchdog.pid"
  start_watchdog
}

kick() {
  restart_watchdog_if_script_changed
  sh "$MODDIR/watchdog.sh" tick >/dev/null 2>&1 &
}

if [ "$1" = "--now" ]; then
  kick
  exit 0
fi

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

if ! pm path "$PKG" >/dev/null 2>&1; then
  rm -rf /data/adb/modules/rclone-android
  rm -f /data/adb/service.d/rclone-android.sh
  exit 0
fi

off=0
if [ -f "$SETTINGS" ] && grep -Eq '"startOnBoot":[[:space:]]*false' "$SETTINGS"; then
  off=1
fi
if [ -f "$BOOTPREF" ] && grep -Eq '"startOnBoot":[[:space:]]*false' "$BOOTPREF"; then
  off=1
fi
if [ "$off" -eq 1 ]; then
  exit 0
fi

kick
sleep 8
am start-foreground-service -n "$SVC" >/dev/null 2>&1 || true
