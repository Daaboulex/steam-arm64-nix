{
  lib,
  buildFHSEnv,
  runCommand,
}:
let
  guestRun = runCommand "steam-arm64-guest-run" { } ''
    install -Dm755 ${./guest-run.sh} "$out"
  '';
in
buildFHSEnv {
  name = "steam-arm64-fhs";

  multiArch = false;

  targetPkgs =
    pkgs: with pkgs; [
      bash
      coreutils
      file
      lsb-release
      pciutils
      usbutils
      xdg-utils
      xz
      zenity

      glibc
      libxcrypt
      libGL
      libdrm
      libgbm
      libva
      vulkan-loader
      udev
      libcap
      networkmanager

      xorg.libX11
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libxcb
      libxkbcommon
      wayland

      alsa-lib
      libpulseaudio
      nss
      nspr
      at-spi2-atk
      cairo
      pango
      gtk3
      gdk-pixbuf
      cups
      dbus
      expat
      fontconfig
      freetype
    ];
  profile = ''
    unset GIO_EXTRA_MODULES
    export SDL_JOYSTICK_DISABLE_UDEV=1
    export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri
    export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d
    export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
  '';

  runScript = "${guestRun}";

  meta = {
    description = "The filesystem layout Valve's aarch64 client expects, with its loader and libraries";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
