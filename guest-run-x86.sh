#!/usr/bin/env bash
set -o nounset

export FEX_ROOTFS=/run/fex-emu/rootfs

mkdir -p /run/dbus 2>/dev/null || true
if [ ! -S /run/dbus/system_bus_socket ]; then
  dbus-daemon --system --fork >/dev/null 2>&1 || true
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

exec @fexinterpreter@ /usr/bin/bash @steam@ -cef-disable-gpu "$@"
