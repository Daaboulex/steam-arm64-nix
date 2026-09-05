#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Valve's x86 client, run the way Fedora Asahi runs it: FEX translating x86
# against a self-contained x86 rootfs, inside muvm's 4K-page guest. The rootfs
# and its overlays are the package's own erofs images, stacked by muvm, so the
# client's whole userland is supplied here and none is borrowed from the host.
#
# The base rootfs is a minimal x86 GL rootfs and carries no coreutils, so the
# coreutils overlay adds the id, true, cp, readlink Valve's launcher and its
# pressure-vessel bwrap need; the mesa overlays add the x86 Mesa that reports
# the GPU. FEX redirects the guest's filesystem into the stacked rootfs, even
# inside pressure-vessel's own sandbox, which is why these tools resolve there.
#
# The Mesa overlay keeps its GL drivers under ovl_dri and its glvnd vendor under
# ovl_egl_vendor.d, off the base rootfs's own search paths, so LIBGL_DRIVERS_PATH
# and the vendor directory are named for the client to find them.
#
# PATH names the rootfs's own bin first so every tool resolves to the x86 rootfs
# under FEX, then the host's for the few the minimal rootfs omits.
guest_env=(
  -e "FEX_ROOTFS=/run/fex-emu/rootfs"
  -e "LIBGL_DRIVERS_PATH=/usr/lib/ovl_dri:/usr/lib32/ovl_dri"
  -e "__EGL_VENDOR_LIBRARY_DIRS=/usr/share/glvnd/ovl_egl_vendor.d"
  -e "PATH=@fexbin@:/usr/bin:/bin:/usr/sbin:/sbin:/run/current-system/sw/bin"
)

# Diagnostics are carried in when the caller sets them: the GL variables, the
# runtime switch, and every FEX_ variable for the translator, which muvm
# forwards none of on its own.
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
  -f "@rootfs@" \
  -f "@coreutils@" \
  -f "@mesaI386@" \
  -f "@mesaX8664@" \
  --gpu-mode=drm \
  --interactive \
  "${guest_env[@]}" \
  -- \
  "@fexinterpreter@" /usr/bin/bash "@steam@" "$@"
