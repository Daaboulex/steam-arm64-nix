#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

resources=$("@xrdb@" -query 2>/dev/null || true)
xresource() {
  printf '%s\n' "$resources" | sed -n "s/^$1:[[:space:]]*\(.*\)\$/\1/p" | head -1
}

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

guest_env=(
  -e "PRESSURE_VESSEL_EMULATOR=@emulator@"
  -e "PATH=@fexbin@:@fexsuite@:@socatbin@:/usr/bin:/bin:/usr/sbin:/sbin"
  -e "MESA_SHADER_CACHE_MAX_SIZE=50G"
)
for var in XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH DBUS_SESSION_BUS_ADDRESS STEAM_EXTRA_COMPAT_TOOLS_PATHS; do
  if [ -n "${!var:-}" ]; then
    guest_env+=(-e "$var=${!var}")
  fi
done

# A launch into a guest that is already running has muvm register its own
# stdin with epoll, which refuses a device or a regular file, so a launch from
# a desktop entry or a link, whose stdin is /dev/null, dies after the request
# went out. A pipe at end of file reads the same and is accepted.
if [ ! -t 0 ] && { [ -c /dev/stdin ] || [ -f /dev/stdin ]; }; then
  exec < <(:)
fi

exec "@muvm@" \
  -f "@rootfs@" \
  --gpu-mode=drm \
  --interactive \
  "${guest_env[@]}" \
  -- \
  "@fhs@/bin/steam-x86-fhs" "$@"
