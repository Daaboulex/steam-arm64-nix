#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

if [ -e /usr/lib64/locale/locale-archive ]; then
  export LOCALE_ARCHIVE=/usr/lib64/locale/locale-archive
fi

steam_root="${STEAM_ARM64_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/Steam}"

if [ -n "${STEAM_COMPAT_GRAPHICS_PROVIDER:-}" ] && [ ! -f "$STEAM_COMPAT_GRAPHICS_PROVIDER" ]; then
  echo "steam-arm64: $STEAM_COMPAT_GRAPHICS_PROVIDER is missing, so x86 games will not start: in muvm's guest, the running guest was started by another command and has no FEX rootfs until it exits; on the host, programs.steam-arm64.hostBinfmt mounts it" >&2
fi

system_bus="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/system_bus"
if [ -S "$system_bus" ] && DBUS_SYSTEM_BUS_ADDRESS="unix:path=$system_bus" dbus-send --system \
  --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
  export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$system_bus"
elif ! dbus-send --system --print-reply --dest=org.freedesktop.DBus \
  / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
  echo "steam-arm64: no system bus answers; Steam cannot read the network state" >&2
fi

if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if ! dbus-send --session --print-reply --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    echo "steam-arm64: the desktop bus does not answer" >&2
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
  check "the client runs on 4K pages" test "$(getconf PAGESIZE)" = 4096
  check "x86-64 binfmt handler registered" test -f /proc/sys/fs/binfmt_misc/FEX-x86_64
  check "FEX rootfs mounted" test -d /run/fex-emu/rootfs/usr/lib64
  check "graphics provider named and present" test -f "${STEAM_COMPAT_GRAPHICS_PROVIDER:-/nonexistent}"
  check "an x86-64 binary runs through the rootfs" test "$(FEX_ROOTFS=/run/fex-emu/rootfs /run/fex-emu/rootfs/usr/bin/echo hi 2>/dev/null)" = hi
  check "python3 for Valve's FEX tool" command -v python3
  check "cursor theme path handed in" test -n "${XCURSOR_PATH:-}"
  check "session bus answers" dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames
  check "host NetworkManager answers on the system bus" dbus-send --system --print-reply --dest=org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.DBus.Properties.Get string:org.freedesktop.NetworkManager string:State
  check "launcher service on PATH" command -v steam-runtime-launcher-service
  check "Valve's FEX tool installed (Steam app 3127680)" test -x "$tools/FEX-Emu/fex-compat-tool"
  check "Valve's FEX tool starts" env STEAM_COMPAT_DATA_PATH=/tmp "$tools/FEX-Emu/fex-compat-tool" --help
  check "Steam Linux Runtime 4.0 arm64 installed (app 4185400)" test -x "$tools/SteamLinuxRuntime_4-arm64/pressure-vessel/bin/pressure-vessel-wrap"
  # shellcheck disable=SC2016
  check "Proton (ARM64) installed" sh -c 'ls -d "$1"/Proton*ARM64*/proton >/dev/null 2>&1' sh "$tools"
  check "GPU render node visible to the client" test -e /dev/dri/renderD128
  # shellcheck disable=SC2329
  game_sees_gpu() {
    local vulkaninfo=$1 triplet=$2 scratch rc
    shift 2
    scratch=$(mktemp -d)
    # shellcheck disable=SC2016
    STEAM_COMPAT_DATA_PATH="$scratch" STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" "$@" sh -c '
      summary=$("$1" --summary 2>/dev/null)
      case "$summary" in
      *PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU* | *PHYSICAL_DEVICE_TYPE_DISCRETE_GPU*) ;;
      *) exit 1 ;;
      esac
      [ -n "$(ls "/usr/lib/pressure-vessel/overrides/lib/$2/dri")" ] && touch "$3/gpu-reached"
    ' sh "$vulkaninfo" "$triplet" "$scratch" || true
    rc=0
    test -e "$scratch/gpu-reached" || rc=1
    rm -rf -- "$scratch"
    return "$rc"
  }
  check "an aarch64 game gets the GPU's Vulkan and GL drivers (Runtime 4.0 arm64)" \
    game_sees_gpu vulkaninfo aarch64-linux-gnu \
    "$tools/SteamLinuxRuntime_4-arm64/_v2-entry-point" --verb=waitforexitandrun --
  check "an x86-64 game under FEX gets the GPU's Vulkan and GL drivers (Runtime 2.0)" \
    game_sees_gpu x86_64-linux-gnu-vulkaninfo x86_64-linux-gnu \
    "$tools/FEX-Emu/fex-compat-tool" waitforexitandrun -- \
    "$tools/SteamLinuxRuntime_soldier/_v2-entry-point" --verb=waitforexitandrun --
  check "audio server socket visible to the client" test -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pipewire-0"
  check "aarch64 overlay library installed" test -f "$steam_root/steamrtarm64/gameoverlayrenderer.so"
  check "x86-64 overlay library for FEX games installed" test -f "$steam_root/ubuntu12_64/gameoverlayrenderer.so"
  check "SteamOS helpers for Deck mode in place" test -x /usr/bin/steamos-polkit-helpers/steamos-update -a -x /usr/bin/steamos-select-branch -a -x /usr/bin/steamos-session-select
  if [ -d /dev/input ]; then
    gamepads=$(find /dev/input -maxdepth 1 -name 'event*' | wc -l)
  else
    gamepads=0
  fi
  printf 'info  gamepads the client can see: %s (inside the muvm guest, muvm forwards each one attached on the host)\n' "$gamepads"
  hidraws=$(find /dev -maxdepth 1 -name 'hidraw*' | wc -l)
  printf 'info  hidraw devices the client can see: %s (always 0 inside the muvm guest, whose kernel has no HID stack, so Steam Input has no gyro, touchpad or lightbar there; on a 4K host they need hardware.steam-hardware.enable for the udev rules)\n' "$hidraws"
  if grep -q binder /proc/filesystems 2>/dev/null; then
    printf 'info  the kernel offers binder, the Android layer could be tried\n'
  else
    printf 'info  the kernel has no binder, so the Android layer (Lepton) cannot run here\n'
  fi
  if [ -s "$steam_root/package/beta" ]; then
    printf 'info  client channel: %s, from package/beta, which the client owns after the first install\n' "$(head -1 "$steam_root/package/beta")"
  else
    printf 'info  client channel: stable, no package/beta\n'
  fi
  if [ -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS:-}" ]; then
    for dir in ${STEAM_EXTRA_COMPAT_TOOLS_PATHS//:/ }; do
      shown=""
      if [ -f "$dir/compatibilitytool.vdf" ]; then
        shown=$(sed -n '/"display_name"/{s/^[[:space:]]*"display_name"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p;q;}' "$dir/compatibilitytool.vdf")
      fi
      check "extra tool ${shown:-${dir%/}} complete" test -f "$dir/toolmanifest.vdf" -a -f "$dir/compatibilitytool.vdf" -a -x "$dir/proton"
    done
  else
    printf 'none  extra compatibility tools handed in\n'
  fi
  exit "$status"
fi

exec "$steam_root/steamrtarm64/steam" "$@"
