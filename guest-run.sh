#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# buildFHSEnv writes its profile to /etc/profile, which only a login shell reads.
if [ -e /usr/lib64/locale/locale-archive ]; then
  export LOCALE_ARCHIVE=/usr/lib64/locale/locale-archive
fi
export XCURSOR_THEME="${XCURSOR_THEME:-breeze_cursors}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"

# The loader enumerates every ICD it finds, so the drivers for hardware this
# machine does not have each fail aloud. Name the ones that can apply instead.
icd=/run/opengl-driver/share/vulkan/icd.d
if [ -d "$icd" ]; then
  drivers=""
  for f in "$icd"/*.json; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
    radeon_* | intel_* | nouveau_* | panfrost_* | broadcom_* | freedreno_* | powervr_* | dzn_*) continue ;;
    esac
    drivers="${drivers:+$drivers:}$f"
  done
  if [ -n "$drivers" ]; then
    export VK_DRIVER_FILES="$drivers"
  fi
fi

steam_root="${STEAM_ARM64_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/Steam}"

# The guest has no session bus of its own and the client's launcher service
# exits without one. A bus that will not start must never stop the client, so
# this is best effort and the client runs either way.
# The desktop's own bus is what the tray needs: an indicator that finds no
# StatusNotifierWatcher falls back to an XEmbed icon, and an XEmbed icon has no
# menu. The host's socket is on the shared filesystem, so try it and prove it
# answers before trusting it; a bus of our own is the fallback.
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    echo "steam-arm64: the desktop bus is not reachable from the guest" >&2
    unset DBUS_SESSION_BUS_ADDRESS
  fi
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if address=$(dbus-daemon --config-file=@dbusConf@ --fork --print-address 2>/dev/null); then
    export DBUS_SESSION_BUS_ADDRESS="$address"
  else
    echo "steam-arm64: no session bus; the launcher service will stay off" >&2
  fi
fi

exec "$steam_root/steamrtarm64/steam" "$@"
