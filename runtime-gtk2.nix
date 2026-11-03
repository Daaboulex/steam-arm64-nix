{
  lib,
  runCommand,
  steam-runtime-arm64,
}:
let
  sonames = [
    "libgtk-x11-2.0.so.0"
    "libgdk-x11-2.0.so.0"
    "libayatana-appindicator.so.1"
    "libayatana-indicator.so.7"
    "libdbusmenu-glib.so.4"
    "libdbusmenu-gtk.so.4"
  ];
  libDir = "${steam-runtime-arm64}/steamrt3c_platform_${steam-runtime-arm64.version}/files/lib/aarch64-linux-gnu";
in
runCommand "steam-runtime-arm64-gtk2-${steam-runtime-arm64.version}"
  {
    meta = {
      description = "The GTK 2 and tray libraries from Valve's aarch64 runtime, which its client links and loads by name";
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-linux" ];
    };
  }
  ''
    mkdir -p "$out/lib"
    for soname in ${lib.escapeShellArgs sonames}; do
      matches=("${libDir}/$soname".*)
      if [ "''${#matches[@]}" -ne 1 ] || [ ! -f "''${matches[0]}" ]; then
        echo "Valve's runtime no longer ships exactly one $soname under ${libDir}" >&2
        exit 1
      fi
      ln -s "''${matches[0]}" "$out/lib/$soname"
    done
    ln -s libayatana-appindicator.so.1 "$out/lib/libappindicator.so.1"
  ''
