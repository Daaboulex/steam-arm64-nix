{
  lib,
  runCommand,
  replaceVars,
  fetchurl,
  gnutar,
  makeDesktopItem,
  xrdb,
  util-linux,
  glibc,
  muvm,
  steam-arm64-client,
  steam-arm64-fhs,
  steam-x86-rootfs,
  channel,
  guest ? true,
  extraCompatTools ? [ ],
}:
let
  launcherTarball = fetchurl {
    url = "https://repo.steampowered.com/steam/archive/stable/steam_1.0.0.87.tar.gz";
    hash = "sha256-ZJN10vk3f4AJqvPi/wmXgEHrkRSJfZxaOIbx2C4nuh8=";
  };
  desktopItem = makeDesktopItem {
    name = "steam-arm64";
    desktopName = "Steam" + lib.optionalString (channel != "stable") " (beta)";
    genericName = "Game Launcher";
    comment = "Valve's native aarch64 Steam client";
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
runCommand
  (
    "steam-arm64"
    + lib.optionalString (channel != "stable") "-beta"
    + lib.optionalString (!guest) "-host"
  )
  {
    meta = {
      description =
        if guest then
          "Valve's aarch64 Steam client, launched in the 4K-page guest its binaries need"
        else
          "Valve's aarch64 Steam client, launched straight on a host whose kernel uses 4K pages";
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      mainProgram = "steam-arm64";
    };
  }
  ''
    install -Dm755 ${
      replaceVars ./launcher.sh {
        client = "${steam-arm64-client}";
        guest = if guest then "1" else "0";
        muvm = lib.optionalString guest (lib.getExe muvm);
        xrdb = lib.getExe' xrdb "xrdb";
        flock = lib.optionalString guest (lib.getExe' util-linux "flock");
        getconf = lib.optionalString (!guest) (lib.getExe' glibc "getconf");
        fhs = "${steam-arm64-fhs}";
        rootfs = lib.optionalString guest "${steam-x86-rootfs}";
        ports = lib.optionalString guest (
          lib.concatMapStringsSep " " (p: "-p ${p}") (import ./ports.nix).published
        );
        compatTools = lib.makeSearchPathOutput "steamcompattool" "" extraCompatTools;
        inherit channel;
      }
    } "$out/bin/steam-arm64"

    ln -s "$out/bin/steam-arm64" "$out/bin/steam"

    for tool in ${lib.escapeShellArgs (map (lib.getOutput "steamcompattool") extraCompatTools)}; do
      test -f "$tool/compatibilitytool.vdf" || {
        echo "$tool is not a Steam compatibility tool: no compatibilitytool.vdf at its root" >&2
        exit 1
      }
    done

    ${lib.optionalString guest "test -s ${steam-x86-rootfs}"}

    ${gnutar}/bin/tar -xzf ${launcherTarball} --strip-components=1 steam-launcher/icons
    for size in 16 24 32 48 256; do
      install -Dm644 "icons/$size/steam.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/steam.png"
    done
    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
