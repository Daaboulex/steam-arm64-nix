{
  lib,
  buildFHSEnv,
  replaceVars,
  runCommand,
  fex,
  fex-interpreter,
  steam-x86-entry,
  fex-emulator-x86,
}:
let
  guestRun = runCommand "steam-x86-guest-run" { } ''
    install -Dm755 ${
      replaceVars ./guest-run-x86.sh {
        fexinterpreter = "${fex-interpreter}/bin/FEXInterpreter";
        steam = "${steam-x86-entry}/bin/steam";
        dbusConf = "${./session-bus.conf}";
        appconfig = "${fex-emulator-x86}/share/fex-emu/AppConfig";
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

      (callPackage ./steamos-stubs.nix {
        shutdown = "exec ${fex-interpreter}/bin/FEXInterpreter /usr/bin/bash ${steam-x86-entry}/bin/steam -shutdown";
      })
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
