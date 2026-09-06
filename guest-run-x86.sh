#!/usr/bin/env bash
set -o nounset

export FEX_ROOTFS=/run/fex-emu/rootfs

mkdir -p /run/dbus 2>/dev/null || true
if [ ! -S /run/dbus/system_bus_socket ]; then
  dbus-daemon --system --fork >/dev/null 2>&1 || true
fi

if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    unset DBUS_SESSION_BUS_ADDRESS
  fi
fi
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if addr=$(dbus-daemon --session --fork --print-address 2>/dev/null); then
    export DBUS_SESSION_BUS_ADDRESS="$addr"
  fi
fi

exec @fexinterpreter@ /usr/bin/bash @steam@ -cef-disable-gpu "$@"
