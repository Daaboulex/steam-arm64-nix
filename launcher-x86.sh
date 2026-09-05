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
# driver paths, which on this machine hold aarch64 objects an x86 client cannot
# load. A command steam-run is given runs after that profile, so the paths named
# here are the ones that survive.
#
# Mesa is named twice, once as a library path and once as a driver path, because
# libglvnd resolves a GLX vendor before it ever reads a driver path: it dlopens
# libGLX_mesa.so.0, falls back to libGLX_indirect.so.0, and with neither present
# glXChooseVisual returns NULL having said nothing about drivers. steam-run's
# filesystem carries glvnd's dispatch libraries and no vendor at all, because an
# x86 NixOS host supplies the vendor from its own driver directory, which here
# holds aarch64 objects. Both word sizes are named on both paths; the loader
# passes over the one that does not match the process.
#
# Rendering is software because the driver for this GPU is aarch64, so a
# translated x86 client has no hardware path to it.

# Diagnostics are carried in when the caller sets them, because a fault this
# deep is only legible from the layer that met it: LIBGL_DEBUG and MESA_DEBUG
# for the GL stack, STEAM_RUNTIME to take Valve's own library substitution out
# of the picture, and every FEX_ variable for the translator itself, which muvm
# forwards none of.
guest_env=(-e "PATH=@fexbin@:/run/current-system/sw/bin")

carry() {
  local name
  for name; do
    if [ -n "${!name:-}" ]; then
      guest_env+=(-e "$name=${!name}")
    fi
  done
}

carry LIBGL_DEBUG MESA_DEBUG STEAM_RUNTIME
carry $(env | sed -n 's/^\(FEX_[A-Z0-9_]*\)=.*/\1/p')

exec "@muvm@" \
  --gpu-mode=drm \
  --interactive \
  "${guest_env[@]}" \
  -- \
  "@fexinterpreter@" "@shell@" "@steamrun@" /bin/bash -c '
    export LD_LIBRARY_PATH="@mesa32@/lib:@mesa64@/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LIBGL_DRIVERS_PATH="@mesa32@/lib/dri:@mesa64@/lib/dri"
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
    exec "@steam@" "$@"
  ' steam-x86 "$@"
