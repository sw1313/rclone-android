#!/system/bin/sh
# 独立于 App：读规则、用 iw 看 WiFi、按现状挂载/卸载。
MODDIR=${MODDIR:-${0%/*}}
[ -f "$MODDIR/common.sh" ] || MODDIR=/data/adb/modules/rclone-android
# shellcheck source=/dev/null
. "$MODDIR/common.sh"
rotate_log
load_paths

LOCK=$MODDIR/lock.d

lock_holder_alive() {
  old=$(cat "$LOCK/pid" 2>/dev/null)
  [ -n "$old" ] || return 1
  [ -d "/proc/$old" ] || return 1
  cmd=$(tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null)
  case "$cmd" in
    *watchdog.sh*) return 0 ;;
  esac
  return 1
}

acquire() {
  n=0
  while [ $n -lt 40 ]; do
    if mkdir "$LOCK" 2>/dev/null; then
      echo $$ > "$LOCK/pid"
      return 0
    fi
    if ! lock_holder_alive; then
      log "清掉过期锁 pid=$(cat "$LOCK/pid" 2>/dev/null)"
      rm -rf "$LOCK"
      continue
    fi
    now=$(date +%s 2>/dev/null || echo 0)
    mt=$(stat -c %Y "$LOCK" 2>/dev/null || echo 0)
    if [ "$now" -gt 0 ] && [ "$mt" -gt 0 ] && [ $((now - mt)) -gt 120 ]; then
      log "锁超过 120 秒，强制解开"
      rm -rf "$LOCK"
      continue
    fi
    n=$((n + 1))
    sleep 0.25
  done
  return 1
}

release() {
  rm -rf "$LOCK"
}

append_unique() {
  # append_unique VAR VALUE  via files in work dir
  echo "$2" >> "$1"
}

uniq_file() {
  sort -u "$1" 2>/dev/null | grep -v '^$' || true
}

do_unmount() {
  id=$1
  quiet=${2:-}
  fuse=$FUSE_ROOT/$id
  local_path=$(kv "$EXPORT/profiles/$id.conf" local)
  rel=$(relative_emulated "$local_path")
  pidf=$FUSE_ROOT/$id.pid
  if [ -f "$pidf" ]; then
    kill -9 "$(cat "$pidf")" 2>/dev/null || true
    rm -f "$pidf"
  fi
  pkill -9 -f "$FUSE_ROOT/$id" 2>/dev/null || true
  lazy() { in_init_ns umount -l "$1" 2>/dev/null || true; }
  if [ -n "$rel" ]; then
    for view in write read default; do
      lazy "/mnt/runtime/$view/emulated/0/$rel"
    done
  fi
  [ -n "$local_path" ] && lazy "$local_path"
  lazy "$fuse"
  in_init_ns grep -F "$FUSE_ROOT/$id" /proc/mounts 2>/dev/null | while read -r _ mp _; do
    [ -n "$mp" ] && lazy "$mp"
  done
  [ "$quiet" = "quiet" ] || log "已卸载 $id"
  [ "$quiet" = "quiet" ] || notify_app
}

do_mount() {
  id=$1
  conf=$EXPORT/profiles/$id.conf
  [ -f "$conf" ] || {
    log "没有配置 $id"
    return 1
  }
  prepare_bins
  if [ -z "$RCLONE" ] || [ ! -f "$RCLONE" ]; then
    log "找不到 rclone，无法挂载 $id"
    return 1
  fi
  name=$(kv "$conf" name)
  remote=$(kv "$conf" remote)
  local_path=$(kv "$conf" local)
  fuse=$FUSE_ROOT/$id
  rel=$(relative_emulated "$local_path")
  cache=$(mount_cache_dir)
  [ -n "$cache" ] || cache=$FILES
  vfs=$cache/vfs
  cfg=$(mount_rclone_conf)
  [ -n "$cfg" ] || cfg=$cache/rclone.conf
  logf=$cache/logs/mount-$id.log
  mkdir -p "$fuse" "$local_path" "$vfs" "$cache/logs" "$HELPER"

  do_unmount "$id" quiet || true

  mode=$(kv "$conf" vfs_cache_mode)
  [ -n "$mode" ] || mode=writes
  gid=$(kv "$conf" gid)
  [ -n "$gid" ] || gid=9997
  umask=$(kv "$conf" umask)
  [ -n "$umask" ] || umask=0
  dir_perms=$(kv "$conf" dir_perms)
  [ -n "$dir_perms" ] || dir_perms=0771
  file_perms=$(kv "$conf" file_perms)
  [ -n "$file_perms" ] || file_perms=0660
  allow=$(kv "$conf" allow_other)
  [ -n "$allow" ] || allow=1
  log_level=$(kv "$conf" log_level)
  [ -n "$log_level" ] || log_level=INFO

  set -- "$RCLONE" mount "$remote" "$fuse" \
    --config "$cfg" \
    --cache-dir "$vfs" \
    --vfs-cache-mode "$mode" \
    --log-level "$log_level" \
    --umask "$umask" \
    --dir-perms "$dir_perms" \
    --file-perms "$file_perms" \
    --gid "$gid" \
    --allow-non-empty
  [ "$allow" = "0" ] || set -- "$@" --allow-other
  v=$(kv "$conf" vfs_cache_max_size); [ -n "$v" ] && set -- "$@" --vfs-cache-max-size "$v"
  v=$(kv "$conf" vfs_cache_max_age); [ -n "$v" ] && set -- "$@" --vfs-cache-max-age "$v"
  v=$(kv "$conf" dir_cache_time); [ -n "$v" ] && set -- "$@" --dir-cache-time "$v"
  v=$(kv "$conf" buffer_size); [ -n "$v" ] && set -- "$@" --buffer-size "$v"
  v=$(kv "$conf" vfs_read_chunk_size); [ -n "$v" ] && set -- "$@" --vfs-read-chunk-size "$v"
  v=$(kv "$conf" transfers); [ -n "$v" ] && set -- "$@" --transfers "$v"
  v=$(kv "$conf" checkers); [ -n "$v" ] && set -- "$@" --checkers "$v"
  v=$(kv "$conf" bwlimit); [ -n "$v" ] && set -- "$@" --bwlimit "$v"
  v=$(kv "$conf" uid); [ -n "$v" ] && set -- "$@" --uid "$v"
  extra=$(kv "$conf" extra_args)
  if [ -n "$extra" ]; then
    # 用户自定义参数按空白拆开
    # shellcheck disable=SC2086
    set -- "$@" $extra
  fi

  export HOME=$cache
  export RCLONE_CONFIG=$cfg
  export PATH=$HELPER:$MODDIR/bin:/system/bin:/system/xbin:$PATH

  if command -v setsid >/dev/null 2>&1; then
    in_init_ns setsid "$@" >> "$logf" 2>&1 </dev/null &
  else
    in_init_ns "$@" >> "$logf" 2>&1 </dev/null &
  fi
  pid=$!
  echo "$pid" > "$FUSE_ROOT/$id.pid"
  escape_cgroup "$pid"

  ok=0
  i=0
  while [ $i -lt 40 ]; do
    if is_fuse_mounted "$id"; then
      ok=1
      break
    fi
    if [ ! -d "/proc/$pid" ]; then
      break
    fi
    sleep 0.25
    i=$((i + 1))
  done
  if [ "$ok" -ne 1 ]; then
    log "挂载失败 $name"
    tail -n 3 "$logf" 2>/dev/null | while read -r l; do log "$l"; done
    return 1
  fi
  if [ -n "$rel" ]; then
    for view in write read default; do
      dest=/mnt/runtime/$view/emulated/0/$rel
      in_init_ns mkdir -p "$dest"
      in_init_ns mount -o bind "$fuse" "$dest" 2>/dev/null || true
    done
  fi
  in_init_ns mkdir -p "$local_path"
  in_init_ns mount -o bind "$fuse" "$local_path" 2>/dev/null || true
  log "已挂载 $name -> $local_path"
  notify_app
}

ensure_binds() {
  id=$1
  conf=$EXPORT/profiles/$id.conf
  [ -f "$conf" ] || return 0
  is_fuse_mounted "$id" || return 1
  fuse=$FUSE_ROOT/$id
  local_path=$(kv "$conf" local)
  rel=$(relative_emulated "$local_path")
  if [ -n "$rel" ]; then
    for view in write read default; do
      dest=/mnt/runtime/$view/emulated/0/$rel
      if ! in_init_ns grep -Fq " $dest " /proc/mounts 2>/dev/null; then
        in_init_ns mkdir -p "$dest"
        in_init_ns mount -o bind "$fuse" "$dest" 2>/dev/null || true
      fi
    done
  fi
  if [ -n "$local_path" ]; then
    if ! in_init_ns grep -Fq " $local_path " /proc/mounts 2>/dev/null; then
      in_init_ns mkdir -p "$local_path"
      in_init_ns mount -o bind "$fuse" "$local_path" 2>/dev/null || true
    fi
  fi
}

process_cmds() {
  [ -f "$CMD_FILE" ] || return 0
  cmds=$CMD_FILE.work
  mv "$CMD_FILE" "$cmds" 2>/dev/null || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    set -- $line
    cmd=$1
    id=$2
    case "$cmd" in
      mount)
        [ -n "$id" ] || continue
        del_list_file "$SKIP_MOUNT" "$id"
        add_list_file "$SKIP_UNMOUNT" "$id"
        if ! is_fuse_mounted "$id"; then
          do_mount "$id" || true
        fi
        ;;
      unmount)
        [ -n "$id" ] || continue
        del_list_file "$SKIP_UNMOUNT" "$id"
        add_list_file "$SKIP_MOUNT" "$id"
        if is_fuse_mounted "$id"; then
          do_unmount "$id"
        fi
        ;;
      unmount_all)
        for mid in $(list_live_ids); do
          del_list_file "$SKIP_UNMOUNT" "$mid"
          add_list_file "$SKIP_MOUNT" "$mid"
          do_unmount "$mid"
        done
        ;;
      reconcile|tick) ;;
      *) ;;
    esac
  done < "$cmds"
  rm -f "$cmds"
}

event_hit() {
  # event_hit KIND CHANGE TARGET
  kind=$1
  change=$2
  target=$3
  [ -f "$MODDIR/work.events" ] || return 1
  while IFS='|' read -r ek ec et; do
    [ "$ek" = "$kind" ] || continue
    [ "$ec" = "$change" ] || continue
    if [ "$kind" = "wifi" ]; then
      if is_any_token "$target" || match_ssid "$target" "$et"; then
        return 0
      fi
    else
      if is_any_token "$target" || match_vpn "$target" "$et"; then
        return 0
      fi
    fi
  done < "$MODDIR/work.events"
  return 1
}

detect_events() {
  rm -f "$MODDIR/work.events"
  touch "$MODDIR/work.events"
  if [ ! -f "$MODDIR/last_ssid" ] && [ ! -f "$MODDIR/last_vpn" ] && [ ! -f "$MODDIR/last_wifi_up" ]; then
    return 0
  fi
  last_ssid=$(cat "$MODDIR/last_ssid" 2>/dev/null || true)
  last_vpn=$(cat "$MODDIR/last_vpn" 2>/dev/null || true)
  last_up=$(cat "$MODDIR/last_wifi_up" 2>/dev/null || true)
  if [ "$WIFI_UP" -eq 1 ] && [ -z "$CUR_SSID" ]; then
    # 已关联但读不到名字：不造 wifi 边沿，避免 MLO/切换瞬间误挂误卸
    :
  elif [ -n "$CUR_SSID" ] && [ "$CUR_SSID" != "$last_ssid" ]; then
    echo "wifi|connect|$CUR_SSID" >> "$MODDIR/work.events"
    [ -n "$last_ssid" ] && echo "wifi|disconnect|$last_ssid" >> "$MODDIR/work.events"
  elif [ -z "$CUR_SSID" ] && [ -n "$last_ssid" ]; then
    echo "wifi|disconnect|$last_ssid" >> "$MODDIR/work.events"
  fi
  if [ "$WIFI_UP" -eq 1 ] && [ "$last_up" = "0" ] && [ -n "$CUR_SSID" ]; then
    echo "wifi|connect|$CUR_SSID" >> "$MODDIR/work.events"
  fi
  if [ "$WIFI_UP" -eq 0 ] && [ "$last_up" = "1" ]; then
    echo "wifi|disconnect|${last_ssid}" >> "$MODDIR/work.events"
  fi
  for n in $CUR_VPN; do
    [ -n "$n" ] || continue
    echo "$last_vpn" | tr ' ' '\n' | grep -qxF "$n" && continue
    echo "vpn|connect|$n" >> "$MODDIR/work.events"
  done
  for n in $last_vpn; do
    [ -n "$n" ] || continue
    echo "$CUR_VPN" | tr ' ' '\n' | grep -qxF "$n" && continue
    # 旧版只记下 tun0，升级后改记包名，不能当成 VPN 断开
    if is_generic_vpn_iface "$n" && [ -n "$CUR_VPN" ]; then
      continue
    fi
    echo "vpn|disconnect|$n" >> "$MODDIR/work.events"
  done
}

save_net() {
  printf '%s' "$CUR_SSID" > "$MODDIR/last_ssid"
  printf '%s' "$CUR_VPN" > "$MODDIR/last_vpn"
  printf '%s' "$WIFI_UP" > "$MODDIR/last_wifi_up"
}

eval_rules() {
  # 对照 box_for_magisk：每个盘只算出一个 desired（挂或卸），再执行。
  # 只有「挂载」规则能决定该挂；卸载规则不再对同一盘投票，也不再 hold 保盘。
  to_mount=$MODDIR/work.mount
  to_unmount=$MODDIR/work.unmount
  to_seen=$MODDIR/work.seen
  rm -f "$to_mount" "$to_unmount" "$to_seen" "$MODDIR/work.hold"
  touch "$to_mount" "$to_unmount" "$to_seen"

  wifi_mon=$(kv "$STATE" wifi_monitor)
  [ -n "$wifi_mon" ] || wifi_mon=1
  prefer=$(kv "$STATE" prefer_real_mount)
  [ -n "$prefer" ] || prefer=1
  if [ "$wifi_mon" = "0" ] || [ "$prefer" = "0" ]; then
    return 0
  fi
  if [ ! -d "$EXPORT/rules" ] || ! ls "$EXPORT/rules"/*.conf >/dev/null 2>&1; then
    log "规则目录还不可读，本轮跳过"
    return 0
  fi

  for rf in "$EXPORT/rules"/*.conf; do
    [ -f "$rf" ] || continue
    enabled=$(kv "$rf" enabled)
    [ "$enabled" = "0" ] && continue
    kind=$(kv "$rf" kind)
    [ -n "$kind" ] || kind=wifi
    action=$(kv "$rf" action)
    [ -n "$action" ] || action=mount
    ids=$(kv "$rf" profiles)
    [ -n "$ids" ] || continue
    rid=$(kv "$rf" id)
    [ -n "$rid" ] || rid=$(basename "$rf" .conf)
    ssid=$(kv "$rf" ssid)
    trigger=$(kv "$rf" trigger)
    [ -n "$trigger" ] || trigger=connect
    vpn_name=$(kv "$rf" vpn_name)
    vpn_trigger=$(kv "$rf" vpn_trigger)
    [ -n "$vpn_trigger" ] || vpn_trigger=connect

    wifi_v=$(wifi_clause "$trigger" "$ssid" | tr -d '\r')
    wifi_a=$(printf '%s' "$wifi_v" | cut -d'|' -f1)
    vpn_v=$(vpn_clause "$vpn_trigger" "$vpn_name" | tr -d '\r')
    vpn_a=$(printf '%s' "$vpn_v" | cut -d'|' -f1)
    [ "$wifi_a" = "1" ] || wifi_a=0
    [ "$vpn_a" = "1" ] || vpn_a=0

    kind_l=$(lower "$kind")
    holds=0
    if [ "$kind_l" = "vpn" ]; then
      [ "$vpn_a" = "1" ] && holds=1
    elif [ "$kind_l" = "both" ]; then
      [ "$wifi_a" = "1" ] && [ "$vpn_a" = "1" ] && holds=1
    else
      [ "$wifi_a" = "1" ] && holds=1
    fi

    log "规则 $rid $kind_l $action wifi=$wifi_a vpn=$vpn_a holds=$holds ssid=$(token_kind "$ssid") vpn_name=$(token_kind "$vpn_name")"

    oldifs=$IFS
    IFS=,
    for pid in $ids; do
      IFS=$oldifs
      pid=$(printf '%s' "$pid" | tr -d ' ')
      [ -n "$pid" ] || continue
      echo "$pid" >> "$to_seen"
      if [ "$action" = "mount" ] && [ "$holds" = "1" ]; then
        echo "$pid" >> "$to_mount"
        log "要挂 $rid $kind_l"
      fi
    done
    IFS=$oldifs
  done

  if [ "$WIFI_UP" = "0" ]; then
    vpn_mount_ok=0
    for rf in "$EXPORT/rules"/*.conf; do
      [ -f "$rf" ] || continue
      [ "$(kv "$rf" enabled)" = "0" ] && continue
      [ "$(kv "$rf" action)" = "unmount" ] && continue
      kind_l=$(lower "$(kv "$rf" kind)")
      [ "$kind_l" = "wifi" ] && continue
      vt=$(kv "$rf" vpn_trigger)
      [ -n "$vt" ] || vt=connect
      [ "$(lower "$vt")" = "connect" ] || continue
      vn=$(kv "$rf" vpn_name)
      [ "$kind_l" = "vpn" ] && [ -z "$vn" ] && vn=$(kv "$rf" ssid)
      [ "$(token_kind "$vn")" = "any" ] && continue
      vv=$(vpn_clause connect "$vn" | tr -d '\r')
      va=$(printf '%s' "$vv" | cut -d'|' -f1)
      [ "$va" = "1" ] || continue
      if [ "$kind_l" = "both" ]; then
        wvv=$(wifi_clause "$(kv "$rf" trigger)" "$(kv "$rf" ssid)" | tr -d '\r')
        wa=$(printf '%s' "$wvv" | cut -d'|' -f1)
        [ "$wa" = "1" ] || continue
      fi
      vpn_mount_ok=1
      break
    done
    if [ "$vpn_mount_ok" = "0" ]; then
      : > "$to_mount"
      log "没有 WiFi，当前 VPN 不匹配具名挂载规则，不挂"
    fi
  fi

  for pid in $(uniq_file "$to_seen"); do
    if echo "$(uniq_file "$to_mount")" | grep -qxF "$pid"; then
      continue
    fi
    echo "$pid" >> "$to_unmount"
  done
}

apply_desired() {
  eval_rules
  to_mount=$MODDIR/work.mount
  to_unmount=$MODDIR/work.unmount
  for id in $(uniq_file "$to_mount"); do
    del_list_file "$SKIP_UNMOUNT" "$id"
    if in_list_file "$SKIP_MOUNT" "$id"; then
      log "跳过自动挂载 $id（用户刚关掉）"
      continue
    fi
    if ! is_fuse_mounted "$id"; then
      do_mount "$id" || true
    else
      ensure_binds "$id" || true
    fi
  done

  for id in $(uniq_file "$to_unmount"); do
    if echo "$(uniq_file "$to_mount")" | grep -qxF "$id"; then
      continue
    fi
    del_list_file "$SKIP_MOUNT" "$id"
    if in_list_file "$SKIP_UNMOUNT" "$id"; then
      log "跳过自动卸载 $id（用户刚打开）"
      continue
    fi
    if is_fuse_mounted "$id"; then
      do_unmount "$id"
    fi
  done
}

tick() {
  if ! acquire; then
    log "看门狗锁被占用，本轮跳过"
    return 0
  fi
  trap release EXIT
  load_paths
  if ! resolve_config; then
    if wifi_associated; then
      WIFI_UP=1
      CUR_SSID=$(current_ssid)
    else
      WIFI_UP=0
      CUR_SSID=
    fi
    CUR_VPN=$(vpn_text)
    log "状态 WIFI_UP=$WIFI_UP ssid_len=${#CUR_SSID} vpn=${CUR_VPN:-无} cfg=none"
    log "规则还不可读，本轮跳过（未解锁且没有快照）"
    release
    trap - EXIT
    return 0
  fi
  if [ ! -d "/data/user/0/$PKG" ]; then
    if ! pm path "$PKG" >/dev/null 2>&1; then
      log "应用已卸载，停止看门狗并删除模块"
      rm -rf /data/adb/modules/rclone-android
      rm -f /data/adb/service.d/rclone-android.sh
      release
      exit 0
    fi
  fi
  if wifi_associated; then
    WIFI_UP=1
    CUR_SSID=$(current_ssid)
  else
    WIFI_UP=0
    # 没关联时 cmd wifi / iw 可能仍吐出上次名称，不能当成还在那张网上
    CUR_SSID=
  fi
  CUR_VPN=$(vpn_text)
  log "状态 WIFI_UP=$WIFI_UP ssid_len=${#CUR_SSID} vpn=${CUR_VPN:-无} cfg=${CONFIG_SRC:-ce}"
  fp="$CUR_SSID|$WIFI_UP|$CUR_VPN"
  last=$(cat "$MODDIR/last_net" 2>/dev/null || true)
  detect_events
  had_events=0
  if [ -s "$MODDIR/work.events" ]; then
    had_events=1
    rm -f "$SKIP_MOUNT" "$SKIP_UNMOUNT"
  fi
  process_cmds
  # 网络变了时规则说了算，避免 cmd 里残留的 mount 又写回 skip 保盘
  if [ "$had_events" = "1" ]; then
    rm -f "$SKIP_MOUNT" "$SKIP_UNMOUNT"
  fi
  apply_desired
  save_net
  if [ "$fp" != "$last" ]; then
    echo "$fp" > "$MODDIR/last_net"
    if [ "$WIFI_UP" = "1" ] && [ -z "$CUR_SSID" ]; then
      wifi_show="已连接但未读到名称"
    elif [ -n "$CUR_SSID" ]; then
      wifi_show=$CUR_SSID
    else
      wifi_show=无
    fi
    vpn_show=$CUR_VPN
    [ -n "$vpn_show" ] || vpn_show=无
    log "核对：WiFi=$wifi_show VPN=$vpn_show"
  fi
  release
  trap - EXIT
}

mounts_pending() {
  [ -s "$MODDIR/work.mount" ] || return 1
  for id in $(uniq_file "$MODDIR/work.mount"); do
    is_fuse_mounted "$id" || return 0
  done
  return 1
}

boot_followup() {
  n=0
  while [ $n -lt 180 ]; do
    load_paths
    if ce_ready || snapshot_ready; then
      log "配置已就绪，开机核对"
      break
    fi
    n=$((n + 1))
    sleep 5
  done
  # 收工看的是「WiFi 和 VPN 都已经读清，并且规则该挂的已经挂上」。
  # 数据网、WiFi 关闭、没有 VPN，都是明确结果，不会干等 WiFi。
  # Tailscale 这类规则同样参与：VPN 已连上就按规则挂；明确没连就结束。
  # 只有一边还在起来（关联中 / 有网卡但不知道是谁），或该挂还没挂上，才再试。
  last=
  i=0
  while [ $i -lt 8 ]; do
    sh "$MODDIR/watchdog.sh" tick
    wifi=$(wifi_link_state)
    vpn=$(vpn_link_state)
    if mounts_pending; then
      last=
      log "该挂的盘还没挂上，继续核对 wifi=$wifi vpn=$vpn"
    elif [ "$wifi" = "starting" ] || [ "$vpn" = "starting" ]; then
      last=
      log "网络还没读清，继续核对 wifi=$wifi vpn=$vpn"
    else
      pair="$wifi|$vpn"
      if [ "$pair" = "$last" ]; then
        log "开机核对完成 wifi=$wifi vpn=$vpn"
        return 0
      fi
      last=$pair
      log "再确认一次 wifi=$wifi vpn=$vpn"
    fi
    i=$((i + 1))
    sleep 5
  done
  log "开机核对结束，之后只等网络变化"
}

loop() {
  echo $$ > "$MODDIR/watchdog.pid"
  # 开机会话：上一轮的 skip / last_* 会挡住同 SSID 补挂
  rm -f "$SKIP_MOUNT" "$SKIP_UNMOUNT" \
    "$MODDIR/last_ssid" "$MODDIR/last_vpn" "$MODDIR/last_wifi_up" "$MODDIR/last_net"
  log "看门狗已启动 pid=$$"
  n=0
  while [ ! -e /data/misc/net ] && [ $n -lt 60 ]; do
    n=$((n + 1))
    sleep 1
  done
  tick
  # 解锁前第一次 tick 可能没有规则；WiFi 早已连上时 inotify 也不会再响
  ( boot_followup ) &
  INOTIFYD=/system/bin/inotifyd
  [ -x "$INOTIFYD" ] || INOTIFYD=$(command -v inotifyd 2>/dev/null || true)
  if [ -z "$INOTIFYD" ] || [ ! -x "$INOTIFYD" ]; then
    log "没有 inotifyd，只能等 App 的 NetworkCallback 触发"
    wait
    return 0
  fi
  # toybox inotifyd：/data/misc/net 一写就回调，与 box_for_magisk 相同
  while true; do
    if [ -e /data/misc/net/rt_tables ]; then
      "$INOTIFYD" "$MODDIR/net.inotify" /data/misc/net /data/misc/net/rt_tables
    elif [ -e /data/misc/net ]; then
      "$INOTIFYD" "$MODDIR/net.inotify" /data/misc/net
    else
      log "没有 /data/misc/net，等系统就绪"
      sleep 2
      continue
    fi
    log "inotifyd 退出，重新监听"
    sleep 1
  done
}

case "${1:-tick}" in
  loop) loop ;;
  tick) tick ;;
  boot_followup) boot_followup ;;
  mount) echo "mount $2" >> "$CMD_FILE"; tick ;;
  unmount) echo "unmount $2" >> "$CMD_FILE"; tick ;;
  *) tick ;;
esac
