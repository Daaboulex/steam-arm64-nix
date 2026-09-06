{
  lib,
  buildFHSEnv,
  replaceVars,
  runCommand,
  fex,
  steam-x86-entry,
}:
let
  fexInterpreter = runCommand "fex-interpreter" { } ''
    mkdir -p "$out/bin"
    ln -s ${fex}/bin/FEX "$out/bin/FEXInterpreter"
    test -x "$out/bin/FEXInterpreter"
  '';
  guestRun = runCommand "steam-x86-guest-run" { } ''
    install -Dm755 ${
      replaceVars ./guest-run-x86.sh {
        fexinterpreter = "${fexInterpreter}/bin/FEXInterpreter";
        steam = "${steam-x86-entry}/bin/steam";
      }
    } "$out"
  '';
in
buildFHSEnv {
  name = "steam-x86-fhs";
  multiArch = false;

  targetPkgs =
    pkgs: with pkgs; [
      bash
      coreutils
      dbus
      fex
      glibc
      file
      lsb-release
      pciutils
      xz
    ];

  extraBwrapArgs = [
    "--bind-try"
    "/run/fex-emu"
    "/run/fex-emu"
  ];

  runScript = "${guestRun}";

  meta = {
    description = "The aarch64 FHS layout pressure-vessel needs, with FEX, so the x86 client's webhelper container runs";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
