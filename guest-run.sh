#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# buildFHSEnv writes its profile to /etc/profile, which only a login shell reads.
if [ -e /usr/lib64/locale/locale-archive ]; then
  export LOCALE_ARCHIVE=/usr/lib64/locale/locale-archive
fi
export XCURSOR_THEME="${XCURSOR_THEME:-breeze_cursors}"
export XCURSOR_SIZE="${XCURSOR_SIZE:-24}"

steam_root="${STEAM_ARM64_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/Steam}"
exec "$steam_root/steamrtarm64/steam" "$@"
