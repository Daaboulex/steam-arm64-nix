{
  fetchurl,
  runCommand,
  xz,
}:
let
  erofsXz = fetchurl {
    url = "https://github.com/asahi-alarm/asahi-alarm/releases/download/rootfs/default.erofs.xz";
    sha256 = "802d74ed6fa7c8f3a1fbd8fed0ffa2329e250af36b57b0863d3a1ca832dc3b7a";
  };
in
runCommand "steam-x86-fex-rootfs.erofs" { nativeBuildInputs = [ xz ]; } ''
  unxz -c ${erofsXz} > "$out"
''
