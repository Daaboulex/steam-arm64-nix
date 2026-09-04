{
  lib,
  runCommand,
  replaceVars,
  makeDesktopItem,
  muvm,
  steam-arm64-client,
  steam-arm64-fhs,
}:
let
  desktopItem = makeDesktopItem {
    name = "steam-arm64";
    desktopName = "Steam";
    genericName = "Game Launcher";
    exec = "steam-arm64 %U";
    icon = "steam";
    categories = [ "Game" ];
    startupWMClass = "steam";
    mimeTypes = [
      "x-scheme-handler/steam"
      "x-scheme-handler/steamlink"
    ];
  };
in
runCommand "steam-arm64"
  {
    meta = {
      description = "Valve's aarch64 Steam client, launched in the 4K-page guest its binaries need";
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      mainProgram = "steam-arm64";
    };
  }
  ''
    install -Dm755 ${
      replaceVars ./launcher.sh {
        client = "${steam-arm64-client}";
        muvm = lib.getExe muvm;
        fhs = "${steam-arm64-fhs}";
        inherit (import ./client-sources.nix) channel;
      }
    } "$out/bin/steam-arm64"

    install -Dm644 ${steam-arm64-client}/public/steam_tray_mono.png \
      "$out/share/icons/hicolor/32x32/apps/steam.png"
    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
