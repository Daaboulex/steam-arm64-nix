#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Valve's x86 client, run the way Fedora Asahi runs it: FEX translating x86
# inside muvm's 4K-page guest. Nothing here reads the host's binfmt, so it
# behaves the same whether or not the machine registers one.
#
# muvm registers FEX as the guest's own binfmt handler and looks for
# FEXInterpreter on PATH to do it, so the guest is given a PATH that has it.
# Without that the client starts and its x86 children do not.
#
# The Apple GPU driver is aarch64, so an x86 client cannot use it, and glX
# fails outright rather than degrading. It is pointed at the x86 software
# renderer instead: slow, and the alternative is a fatal assert on startup.
#
# The client shares ~/.local/share/Steam with the aarch64 one, which is Valve's
# own arrangement: each architecture keeps its own installed manifest there.

exec "@muvm@" \
  --gpu-mode=drm \
  --interactive \
  -e "PATH=@fexbin@:/run/current-system/sw/bin" \
  -e "LIBGL_DRIVERS_PATH=@x86dri@" \
  -e "LIBGL_ALWAYS_SOFTWARE=1" \
  -e "GALLIUM_DRIVER=llvmpipe" \
  -- \
  "@fexinterpreter@" "@shell@" "@steam@" "$@"
