{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  snapshot = "3c.0.20260729.253765";
in
stdenvNoCC.mkDerivation {
  pname = "steam-runtime-steamrt-arm64";
  version = snapshot;

  src = fetchurl {
    url = "https://repo.steampowered.com/steamrt3c/images/${snapshot}/steam-runtime-steamrt-arm64.tar.xz";
    hash = "sha256-0OIduVOLy9+lG0bwrLuoo9y9bl80WuQQpridm5C30J4=";
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
