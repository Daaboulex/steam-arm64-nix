#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Valve's x86 client, run the way Fedora Asahi runs it: FEX translating x86
# inside muvm's 4K-page guest. Nothing here reads the host's binfmt, so it
# behaves the same whether or not the machine registers one.
#
# It is given a home of its own. The aarch64 client owns ~/.steam and
# ~/.local/share/Steam, and two clients of different architectures sharing one
# library and one runtime tree is how a working install gets broken.
home="${STEAM_X86_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/steam-x86}"
mkdir -p -- "$home"
export HOME="$home"

exec "@muvm@" \
  --gpu-mode=drm \
  --interactive \
  -e "HOME=$home" \
  -- \
  "@fexinterpreter@" "@shell@" "@steam@" "$@"
