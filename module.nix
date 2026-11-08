{
  config,
  lib,
  pkgs,
  options,
  utils,
  ...
}:
let
  cfg = config.programs.steam-arm64;
  granules = {
    "4K" = 4096;
    "16K" = 16384;
    "64K" = 65536;
  };
  inherit (config.boot.kernelPackages) kernel;
  kernelStates =
    name:
    lib.hasAttrByPath [ "configfile" "structuredConfig" "ARM64_${name}_PAGES" "tristate" ] kernel
    && kernel.configfile.structuredConfig."ARM64_${name}_PAGES".tristate == "y";
  kernelPageSizes = lib.attrValues (lib.filterAttrs (name: _: kernelStates name) granules);
  pageSize = if options.programs.steam-arm64.pageSize.isDefined then cfg.pageSize else null;
  pageSizeText =
    if pageSize == null then "an unknown page size" else "${toString pageSize}-byte pages";
  host = pageSize == 4096;
  fexRootfs = "/run/fex-emu/rootfs";
  ports = import ./ports.nix;
  portText =
    feature:
    lib.concatStringsSep ", " (
      map (p: "TCP ${toString p}") feature.tcp
      ++ map (p: "UDP ${toString p}") feature.udp
      ++ map (r: "UDP ${toString r.from} to ${toString r.to}") feature.udpRanges
    );
  openFirewall =
    feature: what:
    lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "open ${portText ports.${feature}} and the discovery port ${portText ports.discovery} on the host's firewall for ${what}: the ports nixpkgs' programs.steam opens for the same option. Both launchers publish the same ports out of muvm's guest, from the one list in ports.nix";
    };
  anyFirewall = cfg.remotePlay.openFirewall || cfg.localNetworkGameTransfers.openFirewall;
  openedPorts =
    proto:
    lib.optionals anyFirewall ports.discovery.${proto}
    ++ lib.optionals cfg.remotePlay.openFirewall ports.remotePlay.${proto}
    ++
      lib.optionals cfg.localNetworkGameTransfers.openFirewall
        ports.localNetworkGameTransfers.${proto};
  elfMagics = {
    FEX-x86_64 = utils.binfmtMagics.x86_64-linux;
    FEX-i386 = utils.binfmtMagics.i386-linux;
  };
  registration = magic: {
    inherit (magic) magicOrExtension mask;
    interpreter = "${pkgs.fex}/bin/FEX";
    preserveArgvZero = true;
    openBinary = true;
    matchCredentials = true;
    fixBinary = true;
    wrapInterpreterInShell = false;
  };
  handlersOf =
    magic:
    lib.attrNames (
      lib.filterAttrs (
        _: r: r.magicOrExtension == magic.magicOrExtension
      ) config.boot.binfmt.registrations
    );
  crowdedMagics = lib.filterAttrs (_: magic: lib.length (handlersOf magic) != 1) elfMagics;
  forHost =
    launcher: tools:
    launcher.override {
      guest = !host;
      extraCompatTools = tools;
    };
in
{
  options.programs.steam-arm64 = {
    enable = lib.mkEnableOption "Valve's aarch64 Steam client: inside muvm's 4K-page guest on a 16K or 64K kernel, straight on the host on a 4K kernel";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.steam-arm64;
      defaultText = lib.literalExpression "pkgs.steam-arm64";
      apply = launcher: forHost launcher cfg.extraCompatPackages;
      description = "the native client's launcher from this flake's overlay; pkgs.steam-arm64-beta pins Valve's publicbeta channel. The module rebuilds it for the kernel's page size and with extraCompatPackages";
    };
    pageSize = lib.mkOption {
      type = lib.types.enum (lib.attrValues granules);
      description = "the kernel's page size in bytes, which decides whether the clients run on the host (4096) or inside muvm's guest. Derived from the kernel's configuration when it states ARM64_4K_PAGES, ARM64_16K_PAGES or ARM64_64K_PAGES; state it only when the kernel does not, with the value getconf PAGESIZE prints";
    };
    hostBinfmt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "register FEX as the host's x86-64 and i386 binfmt handler (FEX-x86_64 and FEX-i386, opened at registration so x86 binaries still run inside pressure-vessel's containers), mount the FEX rootfs at /run/fex-emu/rootfs and set FEX_ROOTFS session-wide: what x86 games, x86 Proton and steam-x86 need on a 4K-page host. On the other page sizes muvm's guest does all of this itself";
    };
    extraCompatPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "aarch64 compatibility tools for the native client's dropdown, each with a steamcompattool output or a compatibilitytool.vdf at its root, as programs.steam.extraCompatPackages takes them";
    };
    remotePlay.openFirewall = openFirewall "remotePlay" "Remote Play and Steam Link, whose discovery broadcast cannot leave the guest, so a LAN device reaches this client through these ports alone";
    localNetworkGameTransfers.openFirewall = openFirewall "localNetworkGameTransfers" "game transfers from another Steam client on the LAN";
    x86 = {
      enable = lib.mkEnableOption "Valve's x86-64 Steam client beside the native one, translated by FEX: inside muvm's guest off a 4K kernel, under the host's FEX on one";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.steam-x86;
        defaultText = lib.literalExpression "pkgs.steam-x86";
        apply = launcher: forHost launcher cfg.x86.extraCompatPackages;
        description = "the x86 client's launcher from this flake's overlay, rebuilt by the module for the kernel's page size and with x86.extraCompatPackages";
      };
      extraCompatPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "x86-64 compatibility tools for the x86 client's dropdown, built as aarch64-linux derivations (a prebuilt tarball runs nothing at build time, so it needs no x86 builder)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.steam-arm64.pageSize = lib.mkIf (lib.length kernelPageSizes == 1) (
      lib.mkDefault (lib.head kernelPageSizes)
    );

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "programs.steam-arm64: Valve ships this client for aarch64 only; on x86-64 use programs.steam";
      }
      {
        assertion = pkgs ? steam-arm64 && pkgs ? steam-x86 && pkgs ? steam-x86-rootfs;
        message = "programs.steam-arm64: nixpkgs.overlays lacks steam-arm64-nix's overlays.default, which provides steam-arm64, steam-x86 and steam-x86-rootfs";
      }
      {
        assertion = pageSize != null && lib.all (k: k == pageSize) kernelPageSizes;
        message =
          if pageSize == null then
            "programs.steam-arm64.pageSize: the kernel's configuration (${kernel.name}) states ${
              if kernelPageSizes == [ ] then "no ARM64_*_PAGES" else "more than one ARM64_*_PAGES"
            }; state the page size getconf PAGESIZE prints"
          else
            "programs.steam-arm64.pageSize = ${toString pageSize} contradicts the kernel's configuration (${kernel.name}), which states ${
              lib.concatMapStringsSep " and " toString kernelPageSizes
            }";
      }
      {
        assertion = cfg.hostBinfmt -> host;
        message = "programs.steam-arm64.hostBinfmt: FEX runs on 4K-page kernels only and this kernel uses ${pageSizeText}; off 4K the clients run inside muvm's guest, which registers FEX itself";
      }
      {
        assertion = cfg.hostBinfmt -> crowdedMagics == { };
        message = "programs.steam-arm64.hostBinfmt: boot.binfmt.registrations holds ${
          lib.concatStringsSep "; " (
            lib.mapAttrsToList (
              name: magic:
              "${toString (lib.length (handlersOf magic))} handlers for ${name}'s ELF magic (${lib.concatStringsSep ", " (handlersOf magic)})"
            ) crowdedMagics
          )
        }; the kernel runs the first registered and the others never see a binary, so drop the other handler (an x86 entry in boot.binfmt.emulatedSystems, say) or hostBinfmt";
      }
      {
        assertion = cfg.x86.enable && host -> cfg.hostBinfmt;
        message = "programs.steam-arm64.x86: on a 4K-page host the x86 client runs under the host's FEX and needs programs.steam-arm64.hostBinfmt for the binfmt handler and the FEX rootfs";
      }
    ];

    environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.x86.enable cfg.x86.package;

    boot.binfmt.registrations = lib.mkIf cfg.hostBinfmt (lib.mapAttrs (_: registration) elfMagics);

    fileSystems.${fexRootfs} = lib.mkIf cfg.hostBinfmt {
      device = "${pkgs.steam-x86-rootfs}";
      fsType = "erofs";
      options = [
        "loop"
        "ro"
        "nosuid"
        "nodev"
        "nofail"
      ];
    };

    environment.sessionVariables.FEX_ROOTFS = lib.mkIf cfg.hostBinfmt fexRootfs;

    networking.firewall = {
      allowedTCPPorts = openedPorts "tcp";
      allowedUDPPorts = openedPorts "udp";
      allowedUDPPortRanges = openedPorts "udpRanges";
    };
  };
}
