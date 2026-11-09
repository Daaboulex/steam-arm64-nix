{
  lib,
  runCommand,
  replaceVars,
  steam-unwrapped,
  gnutar,
  makeDesktopItem,
  xrdb,
  util-linux,
  glibc,
  muvm,
  steam-x86-fhs,
  steam-x86-rootfs,
  fex-emulator-x86,
  guest ? true,
  forcePage ? false,
  extraCompatTools ? [ ],
}:
let
  desktopItem = makeDesktopItem {
    name = "steam-x86";
    desktopName = "Steam (x86)";
    genericName = "Game Launcher";
    comment =
      if guest then
        "Valve's x86 Steam client, run by FEX inside the 4K-page microVM"
      else
        "Valve's x86 Steam client, run by the host's FEX";
    exec = "steam-x86 %U";
    icon = "steam-x86";
    categories = [ "Game" ];
  };
in
runCommand ("steam-x86" + lib.optionalString (!guest) "-host")
  {
    meta = {
      description =
        if guest then
          "Valve's x86 Steam client, translated by FEX inside a 4K-page guest, in the FHS layout pressure-vessel needs"
        else
          "Valve's x86 Steam client, translated by the host's FEX on a 4K-page kernel, in the FHS layout pressure-vessel needs";
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      mainProgram = "steam-x86";
    };
  }
  ''
    install -Dm755 ${
      replaceVars ./launcher-x86.sh {
        guest = if guest then "1" else "0";
        muvm = lib.optionalString guest (lib.getExe muvm);
        xrdb = lib.getExe' xrdb "xrdb";
        forcePage = if forcePage then "1" else "0";
        flock = lib.optionalString guest (lib.getExe' util-linux "flock");
        getconf = lib.optionalString (!guest) (lib.getExe' glibc "getconf");
        rootfs = lib.optionalString guest "${steam-x86-rootfs}";
        ports = lib.optionalString guest (
          lib.concatMapStringsSep " " (p: "-p ${p}") (import ./ports.nix).published
        );
        emulator = "${fex-emulator-x86}/emulator.json";
        fhs = "${steam-x86-fhs}";
        compatTools = lib.makeSearchPathOutput "steamcompattool" "" extraCompatTools;
      }
    } "$out/bin/steam-x86"

    for tool in ${lib.escapeShellArgs (map (lib.getOutput "steamcompattool") extraCompatTools)}; do
      test -f "$tool/compatibilitytool.vdf" || {
        echo "$tool is not a Steam compatibility tool: no compatibilitytool.vdf at its root" >&2
        exit 1
      }
    done

    ${lib.optionalString guest "test -s ${steam-x86-rootfs}"}
    test -e ${fex-emulator-x86}/emulator.json
    test -x ${steam-x86-fhs}/bin/steam-x86-fhs

    ${gnutar}/bin/tar -xzf ${steam-unwrapped.src} --strip-components=1 steam-launcher/icons
    for size in 16 24 32 48 256; do
      install -Dm644 "icons/$size/steam.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/steam-x86.png"
    done
    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
