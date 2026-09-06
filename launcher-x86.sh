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
  -e "PATH=@fexbin@:@fexsuite@:/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin"
  -e "DISPLAY=${DISPLAY:-:0}"
  -e "MESA_SHADER_CACHE_MAX_SIZE=50G"
)
for var in XAUTHORITY XCURSOR_THEME XCURSOR_SIZE DBUS_SESSION_BUS_ADDRESS; do
  if [ -n "${!var:-}" ]; then
    guest_env+=(-e "$var=${!var}")
  fi
done

exec "@muvm@" \
  -f "@rootfs@" \
  --gpu-mode=drm \
  --interactive \
  "${guest_env[@]}" \
  -- \
  "@fhs@/bin/steam-x86-fhs" "$@"
