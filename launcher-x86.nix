{
  lib,
  runCommand,
  replaceVars,
  makeDesktopItem,
  muvm,
  fex,
  steam-x86-rootfs,
  steam-x86-coreutils-overlay,
  steam-x86-mesa-overlays,
  steam-x86-entry,
}:
let
  # FEX decides what it is from argv0, and the package ships no FEXInterpreter,
  # so the name it answers to is made here rather than borrowed from the host.
  fexInterpreter = runCommand "fex-interpreter" { } ''
    mkdir -p "$out/bin"
    ln -s ${fex}/bin/FEX "$out/bin/FEXInterpreter"
    test -x "$out/bin/FEXInterpreter"
  '';
  desktopItem = makeDesktopItem {
    name = "steam-x86";
    desktopName = "Steam (x86)";
    genericName = "Game Launcher";
    exec = "steam-x86 %U";
    icon = "steam";
    categories = [ "Game" ];
    startupWMClass = "steam";
    noDisplay = true;
  };
in
runCommand "steam-x86"
  {
    meta = {
      description = "Valve's x86 Steam client, translated by FEX against a self-contained x86 rootfs inside the 4K-page guest";
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      mainProgram = "steam-x86";
    };
  }
  ''
    install -Dm755 ${
      replaceVars ./launcher-x86.sh {
        muvm = lib.getExe muvm;
        fexinterpreter = "${fexInterpreter}/bin/FEXInterpreter";
        fexbin = "${fexInterpreter}/bin";
        rootfs = "${steam-x86-rootfs}";
        coreutils = "${steam-x86-coreutils-overlay}";
        mesaI386 = "${steam-x86-mesa-overlays}/mesa-i386.erofs";
        mesaX8664 = "${steam-x86-mesa-overlays}/mesa-x86_64.erofs";
        steam = "${steam-x86-entry}/bin/steam";
      }
    } "$out/bin/steam-x86"

    test -x ${fexInterpreter}/bin/FEXInterpreter
    test -x ${steam-x86-entry}/bin/steam
    test -s ${steam-x86-rootfs}
    test -s ${steam-x86-coreutils-overlay}
    test -s ${steam-x86-mesa-overlays}/mesa-i386.erofs
    test -s ${steam-x86-mesa-overlays}/mesa-x86_64.erofs

    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
