{
  description = "Valve's aarch64 Steam client packaged for NixOS - pinned from Valve's own client manifest";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.34.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-linux" ];

      imports = [ inputs.std.flakeModules.base ];

      perSystem =
        { system, self', ... }:
        let
          pkgsX86 = import inputs.nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          packages.default = pkgs.callPackage ./package.nix { };
          packages.libdbusmenu-gtk2 = pkgs.callPackage ./libdbusmenu-gtk2.nix { };
          packages.libappindicator-gtk2 = pkgs.callPackage ./libappindicator-gtk2.nix {
            inherit (self'.packages) libdbusmenu-gtk2;
          };
          packages.steam-runtime-arm64 = pkgs.callPackage ./runtime.nix { };
          packages.steam-arm64-fhs = pkgs.callPackage ./fhs.nix {
            inherit (self'.packages) steam-runtime-arm64;
            inherit (self'.packages) libappindicator-gtk2;
          };
          packages.steam-x86 = pkgs.callPackage ./launcher-x86.nix {
            muvm = pkgs.callPackage ./muvm-patched.nix { };
            steam-x86-run = pkgsX86.steam-run;
            steam-x86-entry = pkgsX86.steam-unwrapped;
            steam-x86-shell = pkgsX86.bashInteractive;
            steam-x86-mesa32 = pkgsX86.pkgsi686Linux.mesa;
            steam-x86-mesa64 = pkgsX86.mesa;
          };

          packages.steam-arm64 = pkgs.callPackage ./launcher.nix {
            muvm = pkgs.callPackage ./muvm-patched.nix { };
            steam-arm64-client = self'.packages.default;
            inherit (self'.packages) steam-arm64-fhs;
          };

          pre-commit.settings.hooks = {
            trim-trailing-whitespace.excludes = [ "\\.patch$" ];
            end-of-file-fixer.excludes = [ "\\.patch$" ];
            typos.excludes = [ "\\.patch$" ];
          };

          checks.muvm-patches-apply =
            let
              patched = pkgs.callPackage ./muvm-patched.nix { };
            in
            pkgs.runCommand "muvm-patches-apply" { nativeBuildInputs = [ pkgs.gnupatch ]; } ''
              cp -r ${patched.src} src
              chmod -R +w src
              cd src
              patch -p1 <${./muvm-mask-mit-shm.patch}
              patch -p1 <${./muvm-bridge-dbus.patch}
              touch "$out"
            '';

          checks.muvm-shm-divergence = pkgs.runCommand "muvm-shm-divergence" { } ''
            if grep -q MIT-SHM ${pkgs.muvm.src}/crates/muvm/src/guest/bridge/x11.rs; then
              echo "muvm ${pkgs.muvm.version} now names MIT-SHM in its own X11 bridge."
              echo "Read what it does there. If it masks or proxies the extension,"
              echo "delete muvm-mask-mit-shm.patch, its override in launcher.nix, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.tray-library = pkgs.runCommand "steam-arm64-tray-library" { } ''
            rootfs=$(grep -ao '/nix/store/[a-z0-9]*-steam-arm64-fhs-fhsenv-rootfs' \
              ${self'.packages.steam-arm64-fhs}/bin/steam-arm64-fhs | head -1)
            test -n "$rootfs"
            test -e "$rootfs/usr/lib64/libappindicator.so.1"
            touch "$out"
          '';

          checks.runtime-tools = pkgs.runCommand "steam-arm64-runtime-tools" { } ''
            test -x ${self'.packages.steam-runtime-arm64}/bin/steam-runtime-launcher-service
            test -d ${self'.packages.steam-runtime-arm64}/pressure-vessel
            rootfs=$(grep -ao '/nix/store/[a-z0-9]*-steam-arm64-fhs-fhsenv-rootfs' \
              ${self'.packages.steam-arm64-fhs}/bin/steam-arm64-fhs | head -1)
            test -n "$rootfs"
            grep -q '${self'.packages.steam-runtime-arm64}/bin' "$rootfs/etc/profile"
            test -e "$rootfs/usr/bin/fusermount3"
            touch "$out"
          '';

          checks.overlay-resolves =
            let
              overlaid = import inputs.nixpkgs {
                inherit system;
                config.allowUnfree = true;
                overlays = [ inputs.self.overlays.default ];
              };
            in
            pkgs.runCommand "steam-arm64-overlay-resolves" { } ''
              test -x ${overlaid.steam-arm64}/bin/steam-arm64
              test -x ${overlaid.steam-arm64-fhs}/bin/steam-arm64-fhs
              touch "$out"
            '';

          checks.cursor-theme = pkgs.runCommand "steam-arm64-cursor-theme" { } ''
            rootfs=$(grep -ao '/nix/store/[a-z0-9]*-steam-arm64-fhs-fhsenv-rootfs' \
              ${self'.packages.steam-arm64-fhs}/bin/steam-arm64-fhs | head -1)
            test -n "$rootfs"
            test ! -L "$rootfs/usr/share/icons/default"
            test -f "$rootfs/usr/share/icons/default/cursors/left_ptr"
            touch "$out"
          '';

          checks.steam-x86-really-x86 =
            pkgs.runCommand "steam-x86-really-x86" { nativeBuildInputs = [ pkgs.file ]; }
              ''
                grep -q x86-64 <<<"$(file -bL ${pkgsX86.bashInteractive}/bin/bash)"
                grep -q x86-64 <<<"$(file -bL ${pkgsX86.mesa}/lib/dri/swrast_dri.so)"
                grep -q i386 <<<"$(file -bL ${pkgsX86.pkgsi686Linux.mesa}/lib/dri/swrast_dri.so)"
                touch "$out"
              '';

          checks.client-tree = pkgs.runCommand "steam-arm64-client-tree" { } ''
            test -d ${self'.packages.default}/steamrtarm64/libs
            touch "$out"
          '';
        };

      flake.overlays.default = final: prev: {
        muvm = final.callPackage ./muvm-patched.nix { inherit (prev) muvm; };
        libdbusmenu-gtk2 = final.callPackage ./libdbusmenu-gtk2.nix { };
        libappindicator-gtk2 = final.callPackage ./libappindicator-gtk2.nix { };
        steam-arm64-client = final.callPackage ./package.nix { };
        steam-runtime-arm64 = final.callPackage ./runtime.nix { };
        steam-arm64-fhs = final.callPackage ./fhs.nix { };
        steam-arm64 = final.callPackage ./launcher.nix { };
      };
    };
}
