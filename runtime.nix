{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  source = import ./runtime-source.nix;
in
stdenvNoCC.mkDerivation {
  pname = "steam-runtime-steamrt-arm64";
  version = source.snapshot;

  src = fetchurl {
    url = "${source.baseUrl}/${source.snapshot}/steam-runtime-steamrt-arm64.tar.xz";
    inherit (source) hash;
  };

  sourceRoot = "steam-runtime-steamrt-arm64";

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a . "$out/"
    test -x "$out/bin/steam-runtime-launcher-service"
    test -d "$out/pressure-vessel"
    runHook postInstall
  '';

  meta = {
    description = "Valve's aarch64 Steam Linux Runtime, which carries the launcher service and pressure-vessel the client calls by name";
    homepage = "https://gitlab.steamos.cloud/steamrt/steam-runtime-tools";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-linux" ];
  };
}
