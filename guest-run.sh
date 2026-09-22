#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# buildFHSEnv writes its profile to /etc/profile, which only a login shell reads.
if [ -e /usr/lib64/locale/locale-archive ]; then
  export LOCALE_ARCHIVE=/usr/lib64/locale/locale-archive
fi

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

# muvm keeps one guest per user and a launch into a running guest keeps that
# guest's mounts, so a guest another command started has no FEX rootfs and the
# graphics provider named for Valve's FEX tool points at nothing.
if [ -n "${STEAM_COMPAT_GRAPHICS_PROVIDER:-}" ] && [ ! -f "$STEAM_COMPAT_GRAPHICS_PROVIDER" ]; then
  echo "steam-arm64: $STEAM_COMPAT_GRAPHICS_PROVIDER is not in this guest; x86 games will not start until the running muvm guest exits and Steam starts one of its own" >&2
fi

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

# Valve's aarch64 web helper never carves the input shape of the window it
# embeds, so the client's own title bar and edges never reach the window
# manager: no drag, no resize. The x86 helper carves it, so the client gets
# that helper, run by FEX in this guest, until the aarch64 helper carries the
# shape code itself, which is what the grep on its binary waits for. Valve's
# file check compares sizes, so the swap is padded to the size of the script
# it replaces, and that script is kept beside it.
helper_dir="$steam_root/steamrtarm64"
helper="$helper_dir/steamwebhelper.sh"
pristine="$helper_dir/steamwebhelper.sh.valve"
x86_helper="$steam_root/ubuntu12_64/steamwebhelper.sh"
marker='steam-arm64 hands the x86 web helper to this client'
if grep -q XShapeQueryExtension "$helper_dir/steamwebhelper" 2>/dev/null || [ ! -x "$x86_helper" ]; then
  if [ ! -x "$x86_helper" ]; then
    echo "steam-arm64: no x86 client beside this one, so the window keeps Valve's aarch64 web helper and its title bar cannot move it; run steam-x86 once to install it" >&2
  fi
  if grep -q "$marker" "$helper" 2>/dev/null && [ -f "$pristine" ]; then
    cp -p -- "$pristine" "$helper"
  fi
elif [ -f "$helper" ]; then
  if ! grep -q "$marker" "$helper"; then
    cp -p -- "$helper" "$pristine"
  fi
  swap=$(printf '#!/bin/bash\n# %s\nexport FEX_ROOTFS=/run/fex-emu/rootfs\nunset LIBGL_DRIVERS_PATH __EGL_VENDOR_LIBRARY_DIRS LIBVA_DRIVERS_PATH VDPAU_DRIVER_PATH VK_DRIVER_FILES\nexec FEXInterpreter %s "$@" --disable-gpu --disable-gpu-compositing' "$marker" "$x86_helper")
  size=$(stat -c %s -- "$pristine")
  pad=$((size - ${#swap} - 1))
  if [ "$pad" -lt 0 ]; then
    echo "steam-arm64: Valve's web helper script is shorter than the swap, so the client keeps Valve's aarch64 web helper" >&2
    cp -p -- "$pristine" "$helper"
  elif ! grep -q "$marker" "$helper" || [ "$(stat -c %s -- "$helper")" -ne "$size" ]; then
    printf '%s%*s\n' "$swap" "$pad" '' >"$helper"
  fi
fi

# steam-arm64 --doctor runs here, inside the guest and the sandbox the client
# gets, and reports each thing an x86 game needs, so the stack can be checked
# without launching a game.
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
  tools="$steam_root/steamapps/common"
  check "guest runs on 4K pages" test "$(getconf PAGESIZE)" = 4096
  check "x86-64 binfmt handler registered in the guest" test -f /proc/sys/fs/binfmt_misc/FEX-x86_64
  check "FEX rootfs mounted" test -d /run/fex-emu/rootfs/usr/lib64
  check "graphics provider named and present" test -f "${STEAM_COMPAT_GRAPHICS_PROVIDER:-/nonexistent}"
  check "an x86-64 binary runs through the rootfs" env FEX_ROOTFS=/run/fex-emu/rootfs /run/fex-emu/rootfs/usr/bin/true
  check "python3 for Valve's FEX tool" command -v python3
  check "cursor theme path handed in" test -n "${XCURSOR_PATH:-}"
  check "session bus answers" dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames
  check "launcher service on PATH" command -v steam-runtime-launcher-service
  check "Valve's FEX tool installed (Steam app 3127680)" test -x "$tools/FEX-Emu/fex-compat-tool"
  check "Valve's FEX tool starts" env STEAM_COMPAT_DATA_PATH=/tmp "$tools/FEX-Emu/fex-compat-tool" --help
  check "Steam Linux Runtime 4.0 arm64 installed (app 4185400)" test -x "$tools/SteamLinuxRuntime_4-arm64/pressure-vessel/bin/pressure-vessel-wrap"
  check "Proton (ARM64) installed" sh -c 'ls -d "$1"/Proton*ARM64*/proton >/dev/null 2>&1' sh "$tools"
  check "web helper can move and resize the window (x86 helper, or a fixed aarch64 one)" sh -c 'if ! grep -q "$1" "$2"; then grep -q XShapeQueryExtension "$3"; fi' sh "$marker" "$helper" "$helper_dir/steamwebhelper"
  if [ -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}" ]; then
    for dir in ${STEAM_EXTRA_COMPAT_TOOLS_PATHS//:/ }; do
      check "extra tool ${dir##*/} complete" test -f "$dir/toolmanifest.vdf" -a -f "$dir/compatibilitytool.vdf" -a -x "$dir/proton"
    done
  else
    printf 'none  extra compatibility tools handed in\n'
  fi
  exit "$status"
fi

exec "$steam_root/steamrtarm64/steam" "$@"
