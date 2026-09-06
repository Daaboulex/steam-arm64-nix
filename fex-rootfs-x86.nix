{ fetchurl }:
let
  src = import ./rootfs-source.nix;
in
fetchurl {
  name = "steam-x86-fedora-rootfs.ero";
  inherit (src) url hash;
}
