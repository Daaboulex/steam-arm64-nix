{
  fetchurl,
  runCommand,
  libarchive,
}:
let
  i386pkg = fetchurl {
    url = "https://github.com/asahi-alarm/asahi-alarm/releases/download/archport/mesa-fex-emu-overlay-i386-25.2.4-1-any.pkg.tar.xz";
    sha256 = "e0ad8735878cd5d343f4138ec7f2970119c24b59efe8f3eeb2eb81529f14b18f";
  };
  x64pkg = fetchurl {
    url = "https://github.com/asahi-alarm/asahi-alarm/releases/download/archport/mesa-fex-emu-overlay-x86_64-25.2.4-1-any.pkg.tar.xz";
    sha256 = "186786cde64e7deb5ce1a63289cd872d9a9ab473b3d91f434403d31e24c89c06";
  };
in
runCommand "steam-x86-mesa-overlays" { nativeBuildInputs = [ libarchive ]; } ''
  mkdir -p "$out"
  bsdtar -xOf ${i386pkg} usr/share/fex-emu/overlays/mesa-i386.erofs > "$out/mesa-i386.erofs"
  bsdtar -xOf ${x64pkg} usr/share/fex-emu/overlays/mesa-x86_64.erofs > "$out/mesa-x86_64.erofs"
  test -s "$out/mesa-i386.erofs"
  test -s "$out/mesa-x86_64.erofs"
''
