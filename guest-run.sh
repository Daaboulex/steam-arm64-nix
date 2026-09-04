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

# The guest has no session bus of its own, and steam-runtime-launcher-service
# exits without one. dbus-run-session gives the client a bus for its lifetime.
exec dbus-run-session -- "$steam_root/steamrtarm64/steam" "$@"
