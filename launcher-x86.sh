#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Valve's x86 client, run the way Fedora Asahi runs it: FEX translating x86
# inside muvm's 4K-page guest. Nothing here reads the host's binfmt, so it
# behaves the same whether or not the machine registers one.
#
# muvm registers FEX as the guest's own binfmt handler and looks for
# FEXInterpreter on PATH to do it. Without that the client starts and its x86
# children do not.
#
# The client goes through steam-run rather than the steam wrapper, because that
# wrapper's profile exports LIBGL_DRIVERS_PATH unconditionally at the NixOS
# driver paths, which on this machine hold aarch64 drivers an x86 client cannot
# load. A command steam-run is given runs after that profile, so the drivers
# named here are the ones that survive. They are the software renderer: the
# Apple GPU driver is aarch64, so an x86 client has no hardware path at all, and
# glX fails outright rather than degrading.

exec "@muvm@" \
  --gpu-mode=drm \
  --interactive \
  -e "PATH=@fexbin@:/run/current-system/sw/bin" \
  -- \
  "@fexinterpreter@" "@shell@" "@steamrun@" /bin/bash -c '
    export LIBGL_DRIVERS_PATH="@mesa32@/lib/dri:@mesa64@/lib/dri"
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    exec "@steam@" "$@"
  ' steam-x86 "$@"
