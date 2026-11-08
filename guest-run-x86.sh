#!/usr/bin/env bash
set -o nounset

export FEX_ROOTFS=/run/fex-emu/rootfs
export FEX_APP_CONFIG_LOCATION=@appconfig@

system_bus="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/system_bus"
if [ -S "$system_bus" ] && DBUS_SYSTEM_BUS_ADDRESS="unix:path=$system_bus" dbus-send --system \
  --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
  export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$system_bus"
else
  echo "steam-x86: the host's system bus is not reachable from the guest; Steam cannot read the network state" >&2
  mkdir -p /run/dbus 2>/dev/null || true
  if [ ! -S /run/dbus/system_bus_socket ]; then
    dbus-daemon --system --fork >/dev/null 2>&1 || true
  fi
fi

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [ -S "$runtime_dir/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
fi
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    echo "steam-x86: the desktop bus is not reachable from the guest" >&2
    unset DBUS_SESSION_BUS_ADDRESS
  fi
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if address=$(dbus-daemon --config-file=@dbusConf@ --fork --print-address 2>/dev/null); then
    export DBUS_SESSION_BUS_ADDRESS="$address"
  else
    echo "steam-x86: no session bus; the tray and launcher service stay off" >&2
  fi
fi

if [ "${1:-}" = "--doctor" ]; then
  status=0
  check() {
    name=$1
    shift
    if "$@" >/dev/null 2>&1; then
      printf 'ok    %s\n' "$name"
    else
      printf 'FAIL  %s\n' "$name"
      status=1
    fi
  }
  check "the client runs on 4K pages" test "$(getconf PAGESIZE)" = 4096
  check "x86-64 binfmt handler registered" test -f /proc/sys/fs/binfmt_misc/FEX-x86_64
  check "FEX rootfs mounted" test -d /run/fex-emu/rootfs/usr/lib64
  check "an x86-64 binary runs through the rootfs" test "$(/run/fex-emu/rootfs/usr/bin/echo hi 2>/dev/null)" = hi
  check "Valve's x86 bootstrap present" test -r @steam@
  check "pressure-vessel's emulator manifest present" test -f "${PRESSURE_VESSEL_EMULATOR:-/nonexistent}"
  check "FEX's web helper profile present" test -f @appconfig@/steamwebhelper.json
  check "session bus answers" dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames
  check "SteamOS helpers for Deck mode in place" test -x /usr/bin/steamos-polkit-helpers/steamos-update -a -x /usr/bin/steamos-select-branch -a -x /usr/bin/steamos-session-select
  exit "$status"
fi

exec @fexinterpreter@ /usr/bin/bash @steam@ -cef-disable-gpu "$@"
