{
  lib,
  runCommand,
  replaceVars,
  fetchurl,
  gnutar,
  makeDesktopItem,
  xrdb,
  util-linux,
  muvm,
  fex,
  steam-arm64-client,
  steam-arm64-fhs,
  steam-x86-rootfs,
  channel,
  # Run the client inside a muvm microVM. Needed where the host kernel does not
  # use 4K pages (Asahi Linux); turn it off on a 4K-page host or one without
  # /dev/kvm, where the client runs directly in its FHS sandbox.
  useMuvm ? true,
}:
let
  fexInterpreter = runCommand "fex-interpreter" { } ''
    mkdir -p "$out/bin"
    ln -s ${fex}/bin/FEX "$out/bin/FEXInterpreter"
    test -x "$out/bin/FEXInterpreter"
  '';
  # Valve ships the application icons in its desktop launcher tarball, not in
  # the client payload, which carries only tray icons.
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
runCommand ("steam-arm64" + lib.optionalString (channel != "stable") "-beta")
  {
    meta = {
      description =
        "Valve's aarch64 Steam client"
        + (if useMuvm then ", launched in the 4K-page guest its binaries need" else ", launched directly in its FHS sandbox");
      license = lib.licenses.unfree;
      platforms = [ "aarch64-linux" ];
      mainProgram = "steam-arm64";
    };
  }
  ''
    install -Dm755 ${
      replaceVars ./launcher.sh {
        client = "${steam-arm64-client}";
        useMuvm = if useMuvm then "1" else "0";
        # Left empty without the microVM, so none of them enter the closure.
        muvm = lib.optionalString useMuvm (lib.getExe muvm);
        flock = lib.optionalString useMuvm (lib.getExe' util-linux "flock");
        fexbin = lib.optionalString useMuvm "${fexInterpreter}/bin";
        rootfs = lib.optionalString useMuvm "${steam-x86-rootfs}";
        xrdb = lib.getExe' xrdb "xrdb";
        fhs = "${steam-arm64-fhs}";
        inherit channel;
      }
    } "$out/bin/steam-arm64"

    ln -s "$out/bin/steam-arm64" "$out/bin/steam"

    ${lib.optionalString useMuvm "test -s ${steam-x86-rootfs}"}

    ${gnutar}/bin/tar -xzf ${launcherTarball} --strip-components=1 steam-launcher/icons
    for size in 16 24 32 48 256; do
      install -Dm644 "icons/$size/steam.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/steam.png"
    done
    mkdir -p "$out/share"
    cp -r ${desktopItem}/share/applications "$out/share/"
  ''
