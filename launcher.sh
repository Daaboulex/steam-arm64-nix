#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

xresource() {
  printf '%s\n' "$resources" | sed -n "s/^$1:[[:space:]]*\(.*\)\$/\1/p" | head -1
}

cursor_from_desktop() {
  resources=$("@xrdb@" -query 2>/dev/null || true)
  if [ -z "${XCURSOR_SIZE:-}" ]; then
    size=$(xresource 'Xcursor\.size')
    case "${size:-}" in
    '' | *[!0-9]*) ;;
    *) export XCURSOR_SIZE="$size" ;;
    esac
  fi
  if [ -z "${XCURSOR_THEME:-}" ]; then
    theme=$(xresource 'Xcursor\.theme')
    if [ -n "${theme:-}" ]; then
      export XCURSOR_THEME="$theme"
    fi
  fi
}

require_4k_pages() {
  if [ "$1" != 4096 ]; then
    echo "steam-arm64: this kernel uses $1-byte pages and Valve's client needs 4096; run steam-arm64, which starts it in muvm's 4K-page guest" >&2
    return 1
  fi
}

stdin_as_pipe() {
  if [ ! -t 0 ] && { [ -c /dev/stdin ] || [ -f /dev/stdin ]; }; then
    exec < <(:)
  fi
}

forget_stale_pid() {
  if "@flock@" -n "${XDG_RUNTIME_DIR:?}/muvm.lock" true 2>/dev/null; then
    rm -f -- "$HOME/.steam/steam.pid"
  fi
}

run_in_guest() {
  forget_stale_pid
  "@muvm@" \
    -f "@rootfs@" \
    --gpu-mode=drm \
    -p 27031:27031/udp \
    -p 27036:27036/udp \
    -p 27036:27036 \
    -p 27037:27037 \
    --interactive \
    "${guest_env[@]}" \
    -- \
    "@fhs@/bin/steam-arm64-fhs" "$@"
}

run_on_host() {
  "@fhs@/bin/steam-arm64-fhs" "$@"
}

main() {
  steam_root="${STEAM_ARM64_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/Steam}"

  if [ ! -x "$steam_root/steamrtarm64/steam" ]; then
    echo "steam-arm64: installing the pinned client into $steam_root" >&2
    mkdir -p -- "$steam_root"
    cp --archive --no-target-directory -- "@client@" "$steam_root"
    chmod -R u+rwX -- "$steam_root"
    if [ "@channel@" != stable ]; then
      mkdir -p -- "$steam_root/package"
      printf '%s\n' "@channel@" >"$steam_root/package/beta"
    fi
  fi

  mkdir -p -- "$HOME/.steam" "$steam_root/package"
  ln -sfn -- "$steam_root" "$HOME/.steam/root"
  ln -sfn -- "$steam_root" "$HOME/.steam/steam"
  ln -sfn -- "$steam_root/linuxarm64" "$HOME/.steam/sdkarm64"
  ln -sfn -- "$steam_root/steamrtarm64" "$HOME/.steam/bin64"

  cursor_from_desktop

  export STEAM_ARM64_ROOT="$steam_root"
  export MESA_SHADER_CACHE_MAX_SIZE=50G
  export STEAM_COMPAT_GRAPHICS_PROVIDER=/run/fex-emu/rootfs/graphics_provider.json

  if [ "@guest@" = 1 ]; then
    guest_env=()
    for var in STEAM_ARM64_ROOT MESA_SHADER_CACHE_MAX_SIZE STEAM_COMPAT_GRAPHICS_PROVIDER \
      XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH DBUS_SESSION_BUS_ADDRESS STEAM_EXTRA_COMPAT_TOOLS_PATHS LOCALE_ARCHIVE; do
      if [ -n "${!var:-}" ]; then
        guest_env+=(-e "$var=${!var}")
      fi
    done
    export PATH="@fexbin@:$PATH"
    stdin_as_pipe
    run=run_in_guest
  else
    require_4k_pages "$("@getconf@" PAGESIZE)"
    run=run_on_host
  fi

  while :; do
    status=0
    "$run" "$@" || status=$?
    if [ "$status" -ne 42 ]; then
      return "$status"
    fi
    echo "steam-arm64: Steam asked to restart" >&2
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
