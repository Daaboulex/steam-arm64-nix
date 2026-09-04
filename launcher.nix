{
  lib,
  runCommand,
  replaceVars,
  muvm,
  steam-arm64-client,
  steam-arm64-fhs,
}:
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
  ''
