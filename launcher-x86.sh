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

choose_path() {
  local native switched refusal
  native=$("@getconf@" PAGESIZE)
  if [ "$native" = 4096 ]; then
    path=host
    echo "steam-x86: this kernel uses 4K pages, so the client runs under the host's FEX" >&2
    return 0
  fi
  refusal="this kernel uses $native-byte pages and FEX needs 4096"
  # shellcheck disable=SC2157
  if [ -n "@pageSwitch@" ]; then
    if switched=$("@pageSwitch@" 4k "@getconf@" PAGESIZE 2>&1) && [ "$switched" = 4096 ]; then
      path=switch
      echo "steam-x86: this kernel uses $native-byte pages and @pageSwitch@ gives a program 4K pages, so the client runs under the host's FEX with them" >&2
      return 0
    fi
    refusal="$refusal, and @pageSwitch@ did not give a program 4K pages (it printed: ${switched:-nothing})"
  fi
  # shellcheck disable=SC2050
  if [ "@guest@" = 1 ]; then
    path=guest
    echo "steam-x86: $refusal, so the client runs in muvm's 4K-page guest" >&2
    return 0
  fi
  echo "steam-x86: $refusal; this is the steam-x86-host package, built without muvm's guest: install steam-x86 instead, which starts the client in muvm's 4K-page guest, or let programs.steam-arm64 pick by pageSize" >&2
  return 1
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
  # shellcheck disable=SC2157
  if [ -n "@compatTools@" ]; then
    export STEAM_EXTRA_COMPAT_TOOLS_PATHS="@compatTools@${STEAM_EXTRA_COMPAT_TOOLS_PATHS:+:$STEAM_EXTRA_COMPAT_TOOLS_PATHS}"
  fi

  choose_path
  if [ "$path" = guest ]; then
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
      @ports@ \
      --interactive \
      "${guest_env[@]}" \
      -- \
      "@fhs@/bin/steam-x86-fhs" "$@"
  fi

  if [ "$path" = switch ]; then
    exec "@pageSwitch@" 4k "@fhs@/bin/steam-x86-fhs" "$@"
  fi
  exec "@fhs@/bin/steam-x86-fhs" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
