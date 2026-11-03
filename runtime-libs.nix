{
  lib,
  runCommand,
  patchelf,
  steam-runtime-arm64,
}:
let
  sonames = [
    "libgtk-x11-2.0.so.0"
    "libgdk-x11-2.0.so.0"
    "libayatana-indicator.so.7"
    "libdbusmenu-glib.so.4"
    "libdbusmenu-gtk.so.4"
    "libbz2.so.1.0"
  ];
  libDir = "${steam-runtime-arm64}/steamrt3c_platform_${steam-runtime-arm64.version}/files/lib/aarch64-linux-gnu";
in
runCommand "steam-runtime-arm64-libs-${steam-runtime-arm64.version}"
  {
    nativeBuildInputs = [ patchelf ];
    passthru.sonames = sonames ++ [ "libappindicator.so.1" ];
    meta = {
      description = "The libraries from Valve's aarch64 runtime that its client links or loads under a Debian soname nixpkgs does not answer to";
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "aarch64-linux" ];
    };
  }
  ''
    runtime_file() {
      local matches=("${libDir}/$1".*)
      if [ "''${#matches[@]}" -ne 1 ] || [ ! -f "''${matches[0]}" ]; then
        echo "Valve's runtime no longer ships exactly one $1 under ${libDir}" >&2
        exit 1
      fi
      printf '%s\n' "''${matches[0]}"
    }
    mkdir -p "$out/lib"
    for soname in ${lib.escapeShellArgs sonames}; do
      ln -s "$(runtime_file "$soname")" "$out/lib/$soname"
    done
    cp "$(runtime_file libayatana-appindicator.so.1)" "$out/lib/libappindicator.so.1"
    chmod u+w "$out/lib/libappindicator.so.1"
    patchelf --set-soname libappindicator.so.1 "$out/lib/libappindicator.so.1"
  ''
