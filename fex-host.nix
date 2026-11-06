# NixOS module that gives the host what the muvm microVM otherwise sets up for
# x86 games: the FEX rootfs and an x86 binfmt handler. Use it together with
# `pkgs.steam-arm64.override { useMuvm = false; }`; the overlay must be applied.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.steam-arm64.fexHost;

  # FEX is registered under the name muvm's guest uses, FEXInterpreter, which
  # FEX itself no longer installs.
  fexInterpreter = pkgs.runCommand "fex-interpreter" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.fex}/bin/FEX "$out/bin/FEXInterpreter"
    test -x "$out/bin/FEXInterpreter"
  '';

  # The ELF header patterns qemu-user's binfmt registrations use: class, byte
  # order, ELF version and machine are matched, the OS ABI is not, and both
  # executables and shared objects are accepted.
  mask = ''\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'';

  register = magic: {
    magicOrExtension = magic;
    inherit mask;
    interpreter = "${fexInterpreter}/bin/FEXInterpreter";
    # The default wraps the interpreter in a shell script, which would add a
    # shell start to every x86 process.
    wrapInterpreterInShell = false;
    # FEX's own registration uses the flags POCF. F matters most: the kernel
    # opens the interpreter when it is registered, so x86 binaries still run
    # inside pressure-vessel containers, whose mount namespace has no
    # /nix/store to find FEXInterpreter in.
    preserveArgvZero = true;
    openBinary = true;
    matchCredentials = true;
    fixBinary = true;
  };
in
{
  options.programs.steam-arm64.fexHost = {
    enable = lib.mkEnableOption ''
      the FEX rootfs and the x86 binfmt handler on the host, so x86 Linux games
      and x86 Proton run when steam-arm64 is built with useMuvm = false.
      Needs a kernel with EROFS and binfmt_misc. Do not combine it with
      boot.binfmt.emulatedSystems = [ "x86_64-linux" ], which registers a
      handler for the same binaries
    '';

    rootfs = lib.mkOption {
      type = lib.types.package;
      default = pkgs.steam-x86-rootfs;
      defaultText = lib.literalExpression "pkgs.steam-x86-rootfs";
      description = "The EROFS image mounted at /run/fex-emu/rootfs.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [
      "erofs"
      "loop"
    ];

    fileSystems."/run/fex-emu/rootfs" = {
      device = "${cfg.rootfs}";
      fsType = "erofs";
      options = [
        "loop"
        "ro"
        "nofail"
      ];
    };

    boot.binfmt.registrations = {
      "FEX-x86_64" = register ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
      "FEX-i386" = register ''\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00'';
    };
  };
}
