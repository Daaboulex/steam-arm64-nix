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
    echo "steam-x86: this kernel uses $1-byte pages and FEX needs 4096; run steam-x86, which starts it in muvm's 4K-page guest" >&2
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

main() {
  cursor_from_desktop

  export PRESSURE_VESSEL_EMULATOR="@emulator@"
  export MESA_SHADER_CACHE_MAX_SIZE=50G
  if [ -n "@compatTools@" ]; then
    export STEAM_EXTRA_COMPAT_TOOLS_PATHS="@compatTools@${STEAM_EXTRA_COMPAT_TOOLS_PATHS:+:$STEAM_EXTRA_COMPAT_TOOLS_PATHS}"
  fi

  if [ "@guest@" = 1 ]; then
    guest_env=()
    for var in PRESSURE_VESSEL_EMULATOR MESA_SHADER_CACHE_MAX_SIZE \
      XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH DBUS_SESSION_BUS_ADDRESS STEAM_EXTRA_COMPAT_TOOLS_PATHS LOCALE_ARCHIVE; do
      if [ -n "${!var:-}" ]; then
        guest_env+=(-e "$var=${!var}")
      fi
    done
    stdin_as_pipe
    forget_stale_pid
    exec "@muvm@" \
      -f "@rootfs@" \
      --gpu-mode=drm \
      -p 27031:27031/udp \
      -p 27036:27036/udp \
      -p 27036:27036 \
      -p 27037:27037 \
      --interactive \
      "${guest_env[@]}" \
      -- \
      "@fhs@/bin/steam-x86-fhs" "$@"
  fi

  require_4k_pages "$("@getconf@" PAGESIZE)"
  exec "@fhs@/bin/steam-x86-fhs" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
