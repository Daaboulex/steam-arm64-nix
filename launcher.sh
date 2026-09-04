#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

steam_root="${STEAM_ARM64_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/Steam}"

if [ ! -x "$steam_root/steamrtarm64/steam" ]; then
  echo "steam-arm64: installing the pinned client into $steam_root" >&2
  mkdir -p -- "$steam_root"
  cp --archive --no-target-directory -- "@client@" "$steam_root"
  chmod -R u+rwX -- "$steam_root"
fi

mkdir -p -- "$HOME/.steam" "$steam_root/package"
ln -sfn -- "$steam_root" "$HOME/.steam/root"
ln -sfn -- "$steam_root" "$HOME/.steam/steam"
ln -sfn -- "$steam_root/linuxarm64" "$HOME/.steam/sdkarm64"
# Steam preloads the overlay through .steam/bin64/../steamrtarm64/, so bin64 must resolve.
ln -sfn -- "$steam_root/steamrtarm64" "$HOME/.steam/bin64"

if [ ! -s "$steam_root/package/beta" ]; then
  printf '%s\n' "@channel@" >"$steam_root/package/beta"
fi

# The client draws one device pixel per logical pixel unless it is told the
# desktop's scale, which X publishes as Xft.dpi against a 96 dpi base. Reading
# it here keeps the client following the desktop instead of a pinned number.
if [ -z "${STEAM_SCREEN_SCALE:-}" ]; then
  dpi=$("@xrdb@" -query 2>/dev/null | sed -n 's/^Xft\.dpi:[[:space:]]*\([0-9]\{1,\}\)$/\1/p' | head -1)
  if [ -n "${dpi:-}" ] && [ "$dpi" -gt 96 ]; then
    if STEAM_SCREEN_SCALE=$(awk -v d="$dpi" 'BEGIN { printf "%g", d / 96 }'); then
      export STEAM_SCREEN_SCALE
    fi
  fi
fi

# muvm gives the guest its own environment, so what it must inherit is named here.
guest_env=(-e "STEAM_ARM64_ROOT=$steam_root")
for var in XCURSOR_THEME XCURSOR_SIZE STEAM_SCREEN_SCALE DBUS_SESSION_BUS_ADDRESS; do
  if [ -n "${!var:-}" ]; then
    guest_env+=(-e "$var=${!var}")
  fi
done

# Valve exits 42 to ask for a restart, which is how the client hands control
# back after it updates itself.
while :; do
  set +o errexit
  "@muvm@" \
    --gpu-mode=drm \
    --interactive \
    "${guest_env[@]}" \
    -- \
    "@fhs@/bin/steam-arm64-fhs" "$@"
  status=$?
  set -o errexit

  if [ "$status" -ne 42 ]; then
    exit "$status"
  fi
  echo "steam-arm64: Steam asked to restart" >&2
done
