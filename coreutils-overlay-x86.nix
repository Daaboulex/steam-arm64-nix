{
  runCommand,
  erofs-utils,
  staticPkgs,
}:
let
  tree = runCommand "steam-x86-coreutils-tree" { } ''
    mkdir -p "$out/usr/bin"
    for p in ${staticPkgs.coreutils} ${staticPkgs.gnugrep} ${staticPkgs.gnused} ${staticPkgs.gawk} ${staticPkgs.findutils}; do
      for b in "$p"/bin/*; do
        install -m0755 "$b" "$out/usr/bin/$(basename "$b")"
      done
    done
    install -m0755 ${staticPkgs.busybox}/bin/busybox "$out/usr/bin/busybox"
    ln -sf busybox "$out/usr/bin/cmp"
    ln -sf busybox "$out/usr/bin/diff"
  '';
in
runCommand "steam-x86-coreutils-overlay.erofs" { nativeBuildInputs = [ erofs-utils ]; } ''
  mkfs.erofs -zlz4 "$out" ${tree}
''
