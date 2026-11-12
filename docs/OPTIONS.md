# Options

Every option the modules of this flake declare. This file is generated from the module sources: change a description there, then run `nix run .#std-write-option-reference`.

## NixOS module

Declared in [module.nix](../module.nix).

### `programs.steam-arm64.enable`

Whether to enable Valve's aarch64 Steam client: straight on the host on a 4K kernel; on a 16K or 64K kernel on the host when pageSwitch gives it 4K pages at launch, otherwise inside muvm's 4K-page guest.

- Type: boolean
- Default: `false`

### `programs.steam-arm64.package`

the native client's launcher from this flake's overlay; pkgs.steam-arm64-beta pins Valve's publicbeta channel. The module rebuilds it for the kernel's page size and with extraCompatPackages

- Type: package
- Default: `pkgs.steam-arm64`

### `programs.steam-arm64.extraCompatPackages`

aarch64 compatibility tools for the native client's dropdown, each with a steamcompattool output or a compatibilitytool.vdf at its root, as programs.steam.extraCompatPackages takes them

- Type: list of package
- Default: `[ ]`

### `programs.steam-arm64.hostBinfmt`

register FEX as the host's x86-64 and i386 binfmt handler (FEX-x86_64 and FEX-i386, opened at registration so x86 binaries still run inside pressure-vessel's containers), mount the FEX rootfs at /run/fex-emu/rootfs and set FEX_ROOTFS session-wide: what x86 games, x86 Proton and steam-x86 need on a 4K-page host. On the other page sizes muvm's guest does all of this itself

- Type: boolean
- Default: `false`

### `programs.steam-arm64.localNetworkGameTransfers.openFirewall`

open TCP 27040 and the discovery port UDP 27036 on the host's firewall for game transfers from another Steam client on the LAN: the ports nixpkgs' programs.steam opens for the same option. Both launchers publish the same ports out of muvm's guest, from the one list in ports.nix

- Type: boolean
- Default: `false`

### `programs.steam-arm64.pageSize`

the kernel's page size in bytes, which decides whether the clients run on the host (4096) or inside muvm's guest. Derived from the kernel's configuration when it states ARM64_4K_PAGES, ARM64_16K_PAGES or ARM64_64K_PAGES; state it only when the kernel does not, with the value getconf PAGESIZE prints

- Type: one of 16384, 4096, 65536

### `programs.steam-arm64.pageSwitch`

a program that runs a command with 4K pages on a kernel whose own pages are larger, called as `<program> 4k <command> <args>`, as a kernel built with per-program page sizes may provide one. This package ships no such program and names none to use. Each launch first asks it for 4K pages and runs the clients on the host only when a program started through it reports 4096; otherwise they run in muvm's guest as without it. Null, the default, adds nothing to the closure

- Type: null or package
- Default: `null`

### `programs.steam-arm64.remotePlay.openFirewall`

open TCP 27036, TCP 27037, UDP 10400, UDP 10401, UDP 27031 to 27035 and the discovery port UDP 27036 on the host's firewall for Remote Play and Steam Link, whose discovery broadcast cannot leave the guest, so a LAN device reaches this client through these ports alone: the ports nixpkgs' programs.steam opens for the same option. Both launchers publish the same ports out of muvm's guest, from the one list in ports.nix

- Type: boolean
- Default: `false`

### `programs.steam-arm64.x86.enable`

Whether to enable Valve's x86-64 Steam client beside the native one, translated by FEX: inside muvm's guest off a 4K kernel, under the host's FEX on one.

- Type: boolean
- Default: `false`

### `programs.steam-arm64.x86.package`

the x86 client's launcher from this flake's overlay, rebuilt by the module for the kernel's page size and with x86.extraCompatPackages

- Type: package
- Default: `pkgs.steam-x86`

### `programs.steam-arm64.x86.extraCompatPackages`

x86-64 compatibility tools for the x86 client's dropdown, built as aarch64-linux derivations (a prebuilt tarball runs nothing at build time, so it needs no x86 builder)

- Type: list of package
- Default: `[ ]`
