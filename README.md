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

The client only: no emulation layer, no Proton, no game runtime. The binaries
are aarch64 and run natively; x86 game code still needs FEX and a microVM.

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

## Updates

`scripts/update.sh [publicbeta|stable]` regenerates `client-sources.nix` from
Valve's manifest, which carries each component's sha256.

## License

MIT for the packaging in this repository. Valve's client is unfree and is
marked so in the derivation's `meta`.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
