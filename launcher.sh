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
    echo "steam-arm64: this kernel uses 4K pages, so the client runs on the host" >&2
    return 0
  fi
  refusal="this kernel uses $native-byte pages and Valve's client needs 4096"
  if [ -n "@pageSwitch@" ]; then
    if switched=$("@pageSwitch@" 4k "@getconf@" PAGESIZE 2>&1) && [ "$switched" = 4096 ]; then
      path=switch
      echo "steam-arm64: this kernel uses $native-byte pages and @pageSwitch@ gives a program 4K pages, so the client runs on the host with them" >&2
      return 0
    fi
    refusal="$refusal, and @pageSwitch@ did not give a program 4K pages (it printed: ${switched:-nothing})"
  fi
  if [ "@guest@" = 1 ]; then
    path=guest
    echo "steam-arm64: $refusal, so the client runs in muvm's 4K-page guest" >&2
    return 0
  fi
  echo "steam-arm64: $refusal; this is the steam-arm64-host package, built without muvm's guest: install steam-arm64 instead, which starts the client in muvm's 4K-page guest, or let programs.steam-arm64 pick by pageSize" >&2
  return 1
}

stdin_as_pipe() {
  if [ ! -t 0 ] && { [ -c /dev/stdin ] || [ -f /dev/stdin ]; }; then
    exec < <(:)
  fi
}

restart_loop() {
  local short=0 started status
  while :; do
    started=$SECONDS
    status=0
    "$@" || status=$?
    if [ "$status" -ne 42 ]; then
      return "$status"
    fi
    if [ $((SECONDS - started)) -lt 60 ]; then
      short=$((short + 1))
    else
      short=0
    fi
    if [ "$short" -ge 5 ]; then
      echo "steam-arm64: Steam asked to restart five times in a row without staying up a minute; that is a loop, not an update, so the client stays down" >&2
      return 42
    fi
    echo "steam-arm64: Steam asked to restart" >&2
  done
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
    @ports@ \
    --interactive \
    "${guest_env[@]}" \
    -- \
    "@fhs@/bin/steam-arm64-fhs" "$@"
}

run_on_host() {
  "@fhs@/bin/steam-arm64-fhs" "$@"
}

run_with_switch() {
  "@pageSwitch@" 4k "@fhs@/bin/steam-arm64-fhs" "$@"
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
  if [ -n "@compatTools@" ]; then
    export STEAM_EXTRA_COMPAT_TOOLS_PATHS="@compatTools@${STEAM_EXTRA_COMPAT_TOOLS_PATHS:+:$STEAM_EXTRA_COMPAT_TOOLS_PATHS}"
  fi

  choose_path
  case $path in
  guest)
    guest_env=()
    for var in STEAM_ARM64_ROOT MESA_SHADER_CACHE_MAX_SIZE STEAM_COMPAT_GRAPHICS_PROVIDER \
      XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH DBUS_SESSION_BUS_ADDRESS STEAM_EXTRA_COMPAT_TOOLS_PATHS LOCALE_ARCHIVE; do
      if [ -n "${!var:-}" ]; then
        guest_env+=(-e "$var=${!var}")
      fi
    done
    stdin_as_pipe
    run=run_in_guest
    ;;
  switch) run=run_with_switch ;;
  host) run=run_on_host ;;
  esac

  restart_loop "$run" "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
