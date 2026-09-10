#!/system/bin/sh
# 模块公共函数。由 watchdog.sh / service.sh source。
PKG=com.rcloneandroid.rclone_android
MODDIR=${MODDIR:-/data/adb/modules/rclone-android}
FILES=/data/user/0/$PKG/files
EXPORT=$FILES/module
STATE=$EXPORT/state.conf
CMD_FILE=$MODDIR/cmd
LOG=$MODDIR/watchdog.log
SKIP_MOUNT=$MODDIR/skip_mount
SKIP_UNMOUNT=$MODDIR/skip_unmount
HELPER=/data/local/tmp/rclone-android
FUSE_ROOT=/mnt/rclone

log() {
  ts=$(date '+%H:%M:%S' 2>/dev/null || echo --)
  line="$ts [module] $*"
  mkdir -p "$MODDIR" 2>/dev/null
  echo "$line" >> "$LOG"
  if [ -d "$FILES/logs" ]; then
    echo "$line" >> "$FILES/logs/app.log" 2>/dev/null || true
  fi
}

rotate_log() {
  [ -f "$LOG" ] || return 0
  sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  if [ "$sz" -gt 200000 ] 2>/dev/null; then
    tail -c 80000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
}

kv() {
  # kv FILE KEY
  [ -f "$1" ] || return 0
  grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-
}

lower() {
  printf '%s' "$1" | tr 'A-Z' 'a-z'
}

load_paths() {
  if [ -f "$STATE" ]; then
    FILES=$(kv "$STATE" files_dir)
    [ -n "$FILES" ] || FILES=/data/user/0/$PKG/files
    EXPORT=$FILES/module
    STATE=$EXPORT/state.conf
  fi
}

current_ssid() {
  for dev in wlan0 wlan1 wifi0; do
    [ -d /sys/class/net/$dev ] || continue
    ssid=$(iw dev "$dev" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -n 1)
    [ -z "$ssid" ] && ssid=$(iw "$dev" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p' | head -n 1)
    if [ -n "$ssid" ]; then
      printf '%s' "$ssid"
      return 0
    fi
  done
  # 与 box_for_magisk 相同：cmd wifi status 里的 SSID: "..."
  ssid=$(cmd wifi status 2>/dev/null | sed -n 's/.*SSID: "\([^"]*\)".*/\1/p' | head -n 1)
  if [ -n "$ssid" ] && [ "$ssid" != "<unknown ssid>" ]; then
    printf '%s' "$ssid"
    return 0
  fi
  return 1
}

wifi_associated() {
  for dev in wlan0 wlan1 wifi0; do
    [ -d /sys/class/net/$dev ] || continue
    if iw dev "$dev" link 2>/dev/null | grep -q '^Connected'; then
      return 0
    fi
    if iw "$dev" link 2>/dev/null | grep -q '^Connected'; then
      return 0
    fi
  done
  return 1
}

vpn_ifaces() {
  # tunl0 是内核 IPIP，不是 VpnService
  if [ -d /sys/class/net ]; then
    ls /sys/class/net | grep -E '^(tun|tap|wg|ppp|utun)[0-9]+$|^tailscale[0-9]*$' 2>/dev/null
  fi
}

is_generic_vpn_iface() {
  case "$1" in
    tun[0-9]*|tap[0-9]*|wg[0-9]*|ppp[0-9]*|utun[0-9]*|tailscale*) return 0 ;;
  esac
  return 1
}

vpn_dump_pkg() {
  dump=$(dumpsys vpn_management 2>/dev/null) || return 0
  [ -n "$dump" ] || return 0
  type=$(printf '%s\n' "$dump" | sed -n 's/^[[:space:]]*Active vpn type: //p' | head -n 1)
  pkg=$(printf '%s\n' "$dump" | sed -n 's/^[[:space:]]*Active package name: //p' | head -n 1)
  [ -n "$pkg" ] || pkg=$(printf '%s\n' "$dump" | sed -n 's/^[[:space:]]*[0-9][0-9]*: //p' | head -n 1)
  iface=$(vpn_ifaces | head -n 1)
  # type -1 = 当前没走 VpnService；有 tun 时仍用已登记的包名区分是谁建的
  if [ -z "$iface" ]; then
    case "$type" in
      ""|-1) return 0 ;;
    esac
  fi
  [ -n "$pkg" ] || [ -n "$iface" ] || return 0
  printf '%s\t%s\n' "$pkg" "$iface"
}

vpn_alias_names() {
  pkg=$1
  [ -n "$pkg" ] || return 0
  if [ -f "$EXPORT/vpn_aliases" ]; then
    while IFS='|' read -r p label; do
      [ "$p" = "$pkg" ] || continue
      [ -n "$label" ] && printf '%s\n' "$label"
    done < "$EXPORT/vpn_aliases"
  fi
  case "$pkg" in
    com.tailscale.ipn) printf '%s\n' Tailscale ;;
    com.follow.clash) printf '%s\n' FlClash Clash ;;
  esac
}

vpn_names() {
  rec=$(vpn_dump_pkg)
  if [ -n "$rec" ]; then
    pkg=$(printf '%s' "$rec" | cut -f1)
    iface=$(printf '%s' "$rec" | cut -f2)
    if [ -n "$pkg" ]; then
      printf '%s\n' "$pkg"
      vpn_alias_names "$pkg"
      return 0
    fi
    [ -n "$iface" ] && printf '%s\n' "$iface"
    return 0
  fi
  vpn_ifaces
}

vpn_text() {
  rec=$(vpn_dump_pkg)
  pkg=$(printf '%s' "$rec" | cut -f1)
  iface=$(printf '%s' "$rec" | cut -f2)
  if [ -n "$pkg" ]; then
    printf '%s' "$pkg"
  elif [ -n "$iface" ]; then
    printf '%s' "$iface"
  else
    vpn_ifaces | tr '\n' ' ' | sed 's/[[:space:]]*$//'
  fi
}

match_token() {
  # match_token NEEDLE ITEM
  need=$(lower "$1")
  item=$(lower "$2")
  [ -z "$need" ] && return 0
  [ "$need" = "*" ] && return 0
  [ "$need" = "any" ] && return 0
  [ "$need" = "vpn" ] && return 0
  [ -z "$item" ] && return 1
  [ "$need" = "$item" ] && return 0
  case "$item" in *"$need"*) return 0 ;; esac
  case "$need" in *"$item"*) return 0 ;; esac
  return 1
}

in_init_ns() {
  if [ -r /proc/1/ns/mnt ] && command -v nsenter >/dev/null 2>&1; then
    nsenter -t 1 -m -- "$@"
  else
    "$@"
  fi
}

notify_app() {
  am broadcast -a com.rcloneandroid.rclone_android.REFRESH_STATUS \
    -n "$PKG/.StatusRefreshReceiver" --receiver-foreground >/dev/null 2>&1 || true
}

wifi_clause() {
  # wifi_clause TRIGGER TARGET  → prints active|known
  trigger=$(lower "$1")
  target=$2
  ssid=$CUR_SSID
  any=0
  t=$(lower "$target")
  if [ -z "$t" ] || [ "$t" = "*" ] || [ "$t" = "any" ]; then
    any=1
  fi
  if [ "$any" -eq 1 ]; then
    if [ "$WIFI_UP" -eq 1 ]; then
      matched=1
    else
      matched=0
    fi
    known=1
  else
    matched=0
    if [ -n "$ssid" ] && match_token "$target" "$ssid"; then
      matched=1
    fi
    if [ "$WIFI_UP" -eq 0 ]; then
      known=1
    elif [ -n "$ssid" ]; then
      known=1
    else
      known=0
    fi
  fi
  if [ "$trigger" = "disconnect" ]; then
    if [ "$matched" -eq 0 ] && [ "$known" -eq 1 ]; then
      active=1
    else
      active=0
    fi
  else
    active=$matched
  fi
  printf '%s|%s' "$active" "$known"
}

vpn_clause() {
  trigger=$(lower "$1")
  target=$2
  matched=0
  if [ -z "$(vpn_names)" ]; then
    matched=0
  else
    t=$(lower "$target")
    if [ -z "$t" ] || [ "$t" = "*" ] || [ "$t" = "any" ] || [ "$t" = "vpn" ]; then
      matched=1
    else
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        if match_token "$target" "$n"; then
          matched=1
          break
        fi
      done <<EOF
$(vpn_names)
EOF
    fi
  fi
  if [ "$trigger" = "disconnect" ]; then
    if [ "$matched" -eq 0 ]; then
      active=1
    else
      active=0
    fi
  else
    active=$matched
  fi
  printf '%s|1' "$active"
}

is_fuse_mounted() {
  id=$1
  in_init_ns grep -Eq "[[:space:]]$FUSE_ROOT/$id([[:space:]]|$)" /proc/mounts 2>/dev/null
}

list_live_ids() {
  in_init_ns awk -v p="$FUSE_ROOT/" '
    $2 ~ ("^" p) {
      id=$2
      sub("^" p, "", id)
      sub("/.*", "", id)
      if (id != "" && id != "bin") print id
    }
  ' /proc/mounts 2>/dev/null | sort -u
}

in_list_file() {
  [ -f "$1" ] || return 1
  grep -qxF "$2" "$1" 2>/dev/null
}

add_list_file() {
  mkdir -p "$MODDIR"
  touch "$1"
  if ! grep -qxF "$2" "$1" 2>/dev/null; then
    echo "$2" >> "$1"
  fi
}

del_list_file() {
  [ -f "$1" ] || return 0
  tmp=$1.tmp
  grep -vxF "$2" "$1" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$1"
}

escape_cgroup() {
  pid=$1
  [ -n "$pid" ] || return 0
  [ -d "/proc/$pid" ] || return 0
  if [ -w /sys/fs/cgroup/cgroup.procs ]; then
    echo "$pid" > /sys/fs/cgroup/cgroup.procs 2>/dev/null || true
  fi
  if [ -w /sys/fs/cgroup/memory/cgroup.procs ]; then
    echo "$pid" > /sys/fs/cgroup/memory/cgroup.procs 2>/dev/null || true
  fi
  if [ -w /dev/memcg/cgroup.procs ]; then
    echo "$pid" > /dev/memcg/cgroup.procs 2>/dev/null || true
  fi
}

same_file() {
  [ -f "$1" ] && [ -f "$2" ] || return 1
  s1=$(stat -c %s "$1" 2>/dev/null || wc -c < "$1")
  s2=$(stat -c %s "$2" 2>/dev/null || wc -c < "$2")
  [ "$s1" = "$s2" ]
}

prepare_bins() {
  load_paths
  rclone=$(kv "$STATE" rclone_bin)
  fuse=$(kv "$STATE" fusermount_bin)
  mkdir -p "$MODDIR/bin" "$HELPER" "$FUSE_ROOT/bin"
  if [ -n "$rclone" ] && [ -f "$rclone" ]; then
    if ! same_file "$rclone" "$MODDIR/bin/rclone"; then
      cp -f "$rclone" "$MODDIR/bin/rclone" 2>/dev/null || true
    fi
    chmod 755 "$MODDIR/bin/rclone" 2>/dev/null || true
  fi
  if [ -n "$fuse" ] && [ -f "$fuse" ]; then
    if ! same_file "$fuse" "$MODDIR/bin/fusermount"; then
      cp -f "$fuse" "$MODDIR/bin/fusermount" 2>/dev/null || true
    fi
    if ! same_file "$fuse" "$HELPER/fusermount"; then
      cp -f "$fuse" "$HELPER/fusermount" 2>/dev/null || true
      cp -f "$fuse" "$HELPER/fusermount3" 2>/dev/null || true
    fi
    chmod 755 "$MODDIR/bin/fusermount" "$HELPER/fusermount" "$HELPER/fusermount3" 2>/dev/null || true
  fi
  if [ -x "$MODDIR/bin/rclone" ]; then
    RCLONE=$MODDIR/bin/rclone
  elif [ -n "$rclone" ] && [ -f "$rclone" ]; then
    RCLONE=$rclone
  else
    RCLONE=
  fi
  export PATH=$HELPER:$MODDIR/bin:/system/bin:/system/xbin:$PATH
}

relative_emulated() {
  p=$1
  p=${p%/}
  case "$p" in
    /storage/emulated/0/*) echo "${p#/storage/emulated/0/}" ;;
    /sdcard/*) echo "${p#/sdcard/}" ;;
    /data/media/0/*) echo "${p#/data/media/0/}" ;;
    /mnt/user/0/emulated/0/*) echo "${p#/mnt/user/0/emulated/0/}" ;;
    *) echo "" ;;
  esac
}
