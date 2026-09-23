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
window manager: the window's own chrome cannot move or resize it. The x86 web
helper does carve it, and the traces of both clients prove the difference. The
native client stays purely native all the same, because handing it the x86
helper under FEX made its UI slow, and speed is what the native client is for.
Until Valve's aarch64 helper carries the shape code, KWin moves and resizes the
window as it does any other: Meta with the left button drags it, Meta with the
right button resizes it, and the three title bar buttons work.

Both clients open windows of class `steam`, so only the native client's desktop
entry claims that class and the `steam://` scheme; a second claim would make
the task manager name either client's window after the x86 entry.

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

## What works on this machine

Both clients share one Steam root, so the library, the downloads and the
compatibility tools are the same in each. The native client is the daily one;
the x86 client is the fallback for what the ARM path cannot run. Each row names
its evidence: a Steam log under `logs/`, a launch log, or a probe of the guest.

| Feature | Steam (native) | Steam (x86) | Evidence |
|---|---|---|---|
| Store, library, community | works, native web helper | works, x86 web helper under FEX | both clients' web helper logs |
| Moving and resizing by the window's own chrome | inert: Valve's aarch64 helper carves no input shape; Meta with a mouse button moves and resizes through KWin | works | the traces above |
| Downloads, client updates | works | works | `bootstrap_log.txt`, `content_log.txt` |
| Cloud saves | works | works | `cloud_log.txt` uploads and downloads per app |
| Workshop | works | works | `workshop_log.txt` subscription updates |
| Shader pre-caching | works | works | `shader_log.txt` writes the hit cache for the M1 GPU |
| Windows games | works: Proton 11.0 (ARM64), Proton Experimental (ARM64), GE-Proton aarch64, Proton-CachyOS arm64 | works: Proton 10.0, Experimental, Hotfix | a game ran under GE-Proton11-7; `compat_log.txt` registrations |
| x86 Linux games | wired: Valve's FEX tool, Runtime 4.0 arm64, the rootfs Mesa; no title exercised yet | works, FEX with Runtime sniper | `steam-arm64 --doctor`; the x86 client's own runs |
| aarch64 Linux games | native | not possible | by construction |
| Gamepads | works through muvm's hidpipe, always on: host joysticks recreated by uinput in the guest, rumble included; no hidraw, since the guest kernel has no HID stack, so gyro, touchpad, lightbar and Steam Input's HID drivers are missing (AsahiLinux/muvm#244) | same | `controller.txt`: a DualSense opened in the native client; muvm `hidpipe_server.rs`; libkrunfw's aarch64 config; a guest lists no `/dev/hidraw` |
| Remote Play, Steam Link, LAN transfer | the guest cannot announce itself: passt opens its sockets without broadcast and gives link-local multicast no scope, so the client's UDP broadcast to 27036 and its IPv6 multicast never leave (passt bug 163, open). Both launchers publish UDP 27031 and 27036 and TCP 27036 and 27037, so a LAN device's discovery and stream reach the guest through the host's bound sockets; untested with a device. Pairing by PIN and the same-account host list go through Steam's servers and need no broadcast | same | every launch log; `remote_connections.txt`; passt `udp_flow.c`, `util.c`, `pif.c` |
| In-game overlay | libraries present for aarch64 and, for FEX games, x86-64; attachment under FEX unverified | present | `steamrtarm64/` and `ubuntu12_64/` |
| Game Recording | present, unverified: the logs show it declining a game it is disabled for | same | `console-linux.txt` |
| Big Picture | unverified; one report of the Quick Access Menu freezing the ARM64 client's UI (steam-for-linux#13544, closed unplanned) | unverified | no run yet |
| Audio | works | works | the guest sees `pipewire-0`; `steamui_audio.txt` lists sinks |
| Voice chat, microphone | unverified | unverified | no run yet |
| Screenshots | unverified | unverified | needs the overlay |
| Tray icon, notifications | works over the bridged session bus | works | the launchers' bus checks |
| `steam://` links | works: the native entry owns the scheme | opened by the native client | desktop entries |
| Hardware survey | partial: the GPU is reported, `lspci` finds no `/proc/bus/pci` | partial | `steamsysinfo.txt` |
| Android games (Lepton) | not on this machine: the guest kernel has no binder | not possible | a guest's `/proc/filesystems` |

Valve documents none of this for the desktop arm64 client: no release note, no
support page, no reply on its tracker names it (checked 2026-09-23). What Valve
documents is the mechanism the client uses: the Steam Linux Runtime 4.0 arm64
tool (its README says 32-bit ARM is unsupported), `emulator.json` and
`graphics-provider.json` in steam-runtime-tools, and the Proton README, which
says an ARM64 build cannot be used from the x86 client under FEX. Lepton's README
says it is meant for Steam Frame and that most users should take the Lepton the
client ships.

Two costs of one shared root, accepted for a fallback client: both packages ship
the x86-64 overlay files under `ubuntu12_64/` and `steamrt64/` at different
sizes, so the first start of either client after the other one ran repairs
those files and restarts once; and pressure-vessel regenerates the locales it
misses at each container start, which is upstream noise.

## Updates

`scripts/update.sh [publicbeta|stable]` regenerates `client-sources.nix` from
Valve's manifest, which carries each component's sha256.

## License

MIT for the packaging in this repository. Valve's client is unfree and is
marked so in the derivation's `meta`.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
