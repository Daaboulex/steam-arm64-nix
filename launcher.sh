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

if [ ! -s "$steam_root/package/beta" ]; then
  printf '%s\n' "@channel@" >"$steam_root/package/beta"
fi

# Valve exits 42 to ask for a restart, which is how the client hands control
# back after it updates itself.
while :; do
  set +o errexit
  "@muvm@" \
    --gpu-mode=drm \
    --interactive \
    -e "STEAM_ARM64_ROOT=$steam_root" \
    -- \
    "@fhs@/bin/steam-arm64-fhs" "$@"
  status=$?
  set -o errexit

  if [ "$status" -ne 42 ]; then
    exit "$status"
  fi
  echo "steam-arm64: Steam asked to restart" >&2
done
