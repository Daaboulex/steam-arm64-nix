{
  lib,
  runCommand,
  replaceVars,
  fetchurl,
  gnutar,
  makeDesktopItem,
  xrdb,
  muvm,
  steam-arm64-client,
  steam-arm64-fhs,
}:
let
  # Valve ships the application icons in its desktop launcher tarball, not in
  # the client payload, which carries only tray icons.
  launcherTarball = fetchurl {
    url = "https://repo.steampowered.com/steam/archive/stable/steam_1.0.0.87.tar.gz";
    hash = "sha256-ZJN10vk3f4AJqvPi/wmXgEHrkRSJfZxaOIbx2C4nuh8=";
  };
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
        xrdb = lib.getExe' xrdb "xrdb";
        fhs = "${steam-arm64-fhs}";
        inherit (import ./client-sources.nix) channel;
      }
    } "$out/bin/steam-arm64"

    ${gnutar}/bin/tar -xzf ${launcherTarball} --strip-components=1 steam-launcher/icons
    for size in 16 24 32 48 256; do
      install -Dm644 "icons/$size/steam.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/steam.png"
    done
    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
