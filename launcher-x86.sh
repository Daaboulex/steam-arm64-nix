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

# A few variables are carried in when the caller sets them, because the client
# fails at window creation and the reason lives in what its GL stack says.
# LIBGL_DEBUG=verbose names the driver it tries and why it gives up, and
# STEAM_RUNTIME=0 stops the runtime substituting its own libraries for ours.
guest_env=(-e "PATH=@fexbin@:/run/current-system/sw/bin")
for var in LIBGL_DEBUG STEAM_RUNTIME MESA_DEBUG LIBGL_ALWAYS_INDIRECT; do
  if [ -n "${!var:-}" ]; then
    guest_env+=(-e "$var=${!var}")
  fi
done

exec "@muvm@" \
  --gpu-mode=drm \
  --interactive \
  "${guest_env[@]}" \
  -- \
  "@fexinterpreter@" "@shell@" "@steamrun@" /bin/bash -c '
    export LIBGL_DRIVERS_PATH="@mesa32@/lib/dri:@mesa64@/lib/dri"
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    exec "@steam@" "$@"
  ' steam-x86 "$@"
