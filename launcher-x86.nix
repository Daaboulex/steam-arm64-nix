{
  lib,
  runCommand,
  replaceVars,
  makeDesktopItem,
  muvm,
  fex,
  steam-x86-client,
  steam-x86-shell,
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
      description = "Valve's x86 Steam client, translated by FEX inside the 4K-page guest, for comparing against the aarch64 client";
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
        shell = lib.getExe steam-x86-shell;
        steam = "${steam-x86-client}/bin/steam";
      }
    } "$out/bin/steam-x86"

    test -x ${fexInterpreter}/bin/FEXInterpreter
    test -x ${steam-x86-client}/bin/steam
    test -x ${lib.getExe steam-x86-shell}

    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
