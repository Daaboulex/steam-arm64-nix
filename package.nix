{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
let
  sources = import ./client-sources.nix;
  component =
    name: spec:
    fetchurl {
      name = "steam-arm64-${name}";
      url = "${sources.baseUrl}/${spec.file}";
      inherit (spec) sha256;
    };
  archives = lib.mapAttrsToList component sources.components;
in
stdenvNoCC.mkDerivation {
  pname = "steam-arm64-client";
  inherit (sources) version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ unzip ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    for archive in ${lib.escapeShellArgs archives}; do
      unzip -qq -o "$archive" -d "$out"
    done

    while IFS= read -r -d "" entry; do
      target="$out/$(basename "$entry" | tr '\\' '/')"
      if [ -d "$entry" ]; then
        mkdir -p "$target"
        cp -a "$entry/." "$target/"
        rm -rf "$entry"
        continue
      fi
      if [ -d "$target" ]; then
        echo "$entry collides with the directory $target" >&2
        exit 1
      fi
      mkdir -p "$(dirname "$target")"
      mv "$entry" "$target"
    done < <(find "$out" -mindepth 1 -maxdepth 1 -name '*\\*' -print0)

    test -f "$out/steamrtarm64/steam"

    while IFS= read -r -d "" candidate; do
      case "$(head -c 4 "$candidate" | od -An -tx1 | tr -d ' \n')" in
      7f454c46 | 2321*) chmod +x "$candidate" ;;
      esac
    done < <(find "$out" -type f -print0)

    test -x "$out/steamrtarm64/steam"
    runHook postInstall
  '';

  meta = {
    description = "Valve's native aarch64 Steam client, pinned from Valve's own client manifest";
    homepage = "https://store.steampowered.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-linux" ];
  };
}
