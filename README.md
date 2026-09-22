# Steam for aarch64 (Nix)

<!-- BEGIN generated:badges -->
[![CI](https://github.com/Daaboulex/steam-arm64-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/steam-arm64-nix/actions/workflows/ci.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
<!-- END generated:badges -->

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | [Steam for Linux](https://store.steampowered.com/) |
| **License** | Unfree (Valve) |
| **Tracked** | Valve's linuxarm64 client manifest |

<!-- END generated:upstream -->

Valve's native aarch64 Steam client, packaged for NixOS and pinned from Valve's
own client manifest.

## What Is This?

Two clients. `steam-arm64` is Valve's native aarch64 client, run inside the
4K-page microVM its binaries need. Windows games go through Valve's Proton
(ARM64), Wine built as ARM64EC with FEX inside it; x86 Linux games and x86
Proton go through Valve's own FEX compatibility tool, which the client
downloads, and which takes its x86 Mesa from the FEX rootfs the launcher mounts.
`steam-x86` is Valve's x86_64 client itself, translated by FEX inside the same
microVM, in the FHS layout pressure-vessel needs so its webhelper renders.

## Installation

```nix
{
  inputs.steam-arm64-nix = {
    url = "github:Daaboulex/steam-arm64-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then take `overlays.default`, which provides `steam-arm64-client`. The client is
unfree, so the consumer sets `nixpkgs.config.allowUnfree = true`.

## Usage

The package is the unpacked client tree; its entry point is `steamrtarm64/steam`.
The binaries are unpatched and ask for `/lib/ld-linux-aarch64.so.1`, so running
them needs `programs.nix-ld.enable` or an FHS environment. Valve's client keeps
itself current from the network once it is running.

## Development

```bash
nix build .#packages.aarch64-linux.default
nix flake check
```

Guest output is lost whenever the launcher's own stdout is not a terminal,
because muvm attaches the guest's streams to the terminal it was started from. A
plain redirect keeps muvm's own first line and drops everything the guest says,
which reads as a program that never ran. Capture through a pty instead. Any
`FEX_` variable set on the same command reaches the translator, a namespace muvm
forwards none of.

To test the native aarch64 client:

```bash
script -q -c "nix run .#steam-arm64" steam-arm64.log
```

To test the x86_64 client, translated by FEX inside the microVM:

```bash
script -q -c "nix run .#steam-x86" steam-x86.log
```

## Moving and resizing the native client's window

Valve's aarch64 web helper never carves the input shape of the window it
embeds, so presses on the client's own title bar and edges never reach the
window manager and the window cannot be moved or resized. The x86 web helper
does carve it, so the launcher hands the native client that helper, run by FEX
inside the same guest, on every start: it keeps Valve's script beside the swap
as `steamwebhelper.sh.valve`, pads the swap to the size Valve's file check
expects, and stops swapping by itself once Valve's aarch64 helper carries the
shape code. It needs the x86 client installed in the same Steam root, which
`steam-x86` does on its first run. The UI then renders through FEX, the way the
whole x86 client does.

Valve's client checks file sizes on a normal start, which the padding
satisfies. After an unclean shutdown it checks CRCs instead, reinstalls its own
package over the swap, restarts, and the launcher applies the swap again; that
start takes about a minute longer. Quitting the client cleanly keeps the next
start on the size check.

## Checking the stack

```bash
steam-arm64 --doctor
```

Runs inside the guest and the sandbox the client gets, joining a running
client or starting a guest of its own, and reports each thing an x86 game
needs: the 4K page size, the binfmt handler, the FEX rootfs and the graphics
provider, python3 for Valve's FEX tool, the cursor path, the session bus, and
the Steam apps the client must have downloaded (FEX, Steam Linux Runtime 4.0
arm64, a Proton for ARM64).

Extra compatibility tools reach the client through `STEAM_EXTRA_COMPAT_TOOLS_PATHS`,
the same variable nixpkgs' `programs.steam.extraCompatPackages` sets; both
launchers hand it to the guest when the session has it.

## Updates

`scripts/update.sh [publicbeta|stable]` regenerates `client-sources.nix` from
Valve's manifest, which carries each component's sha256.

## License

MIT for the packaging in this repository. Valve's client is unfree and is
marked so in the derivation's `meta`.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
