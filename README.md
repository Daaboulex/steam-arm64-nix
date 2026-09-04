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

The client only. It carries no emulation layer, no Proton and no games runtime:
the binaries are aarch64 and run natively on Apple Silicon, which is the reason
to prefer this over running the x86 client under FEX. Anything that runs x86
game code still needs FEX and a microVM, which this repository deliberately does
not own.

## Installation

```nix
{
  inputs.steam-arm64-nix.url = "github:Daaboulex/steam-arm64-nix";
}
```

Then take `overlays.default`, which provides `steam-arm64-client`.

## Usage

The package is the unpacked client tree. Its entry point is
`steamrtarm64/steam`, and Valve's client keeps itself current from the network
once it is running, exactly as it does on any other Linux.

## Development

```bash
nix build .#packages.aarch64-linux.default
nix flake check
```

## Updates

`scripts/update.sh [publicbeta|stable]` regenerates `client-sources.nix` from
Valve's manifest. The manifest carries each component's SHA-256 and those are
byte-for-byte the hashes Nix wants, so an update reads one small text file and
downloads nothing.

## License

MIT for the packaging in this repository. Valve's client is unfree and is
marked so in the derivation's `meta`.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
