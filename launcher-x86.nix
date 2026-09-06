{
  lib,
  runCommand,
  replaceVars,
  fetchurl,
  gnutar,
  makeDesktopItem,
  xrdb,
  muvm,
  fex,
  steam-x86-fhs,
  steam-x86-rootfs,
  fex-emulator-x86,
}:
let
  fexInterpreter = runCommand "fex-interpreter" { } ''
    mkdir -p "$out/bin"
    ln -s ${fex}/bin/FEX "$out/bin/FEXInterpreter"
    test -x "$out/bin/FEXInterpreter"
  '';
  launcherTarball = fetchurl {
    url = "https://repo.steampowered.com/steam/archive/stable/steam_1.0.0.87.tar.gz";
    hash = "sha256-ZJN10vk3f4AJqvPi/wmXgEHrkRSJfZxaOIbx2C4nuh8=";
  };
  desktopItem = makeDesktopItem {
    name = "steam-x86";
    desktopName = "Steam (x86)";
    genericName = "Game Launcher";
    exec = "steam-x86 %U";
    icon = "steam-x86";
    categories = [ "Game" ];
    startupWMClass = "steam";
    mimeTypes = [
      "x-scheme-handler/steam"
      "x-scheme-handler/steamlink"
    ];
  };
in
runCommand "steam-x86"
  {
    meta = {
      description = "Valve's x86 Steam client, translated by FEX inside a 4K-page guest, in the FHS layout pressure-vessel needs";
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      mainProgram = "steam-x86";
    };
  }
  ''
    install -Dm755 ${
      replaceVars ./launcher-x86.sh {
        muvm = lib.getExe muvm;
        xrdb = lib.getExe' xrdb "xrdb";
        fexbin = "${fexInterpreter}/bin";
        fexsuite = "${fex}/bin";
        rootfs = "${steam-x86-rootfs}";
        emulator = "${fex-emulator-x86}/emulator.json";
        fhs = "${steam-x86-fhs}";
      }
    } "$out/bin/steam-x86"

    test -x ${fexInterpreter}/bin/FEXInterpreter
    test -s ${steam-x86-rootfs}
    test -e ${fex-emulator-x86}/emulator.json
    test -x ${steam-x86-fhs}/bin/steam-x86-fhs

    ${gnutar}/bin/tar -xzf ${launcherTarball} --strip-components=1 steam-launcher/icons
    for size in 16 24 32 48 256; do
      install -Dm644 "icons/$size/steam.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/steam-x86.png"
    done
    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
