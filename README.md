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
4K-page microVM its binaries need. On 2026-11-03, 33 of the client's 87 ELF
files had LOAD segments aligned below 16K (Steam issue 13745, closed as not
planned), and FEX 2608 aborted on the 16K-page host. `checks.client-needs-4k-pages`
fails the day a client update brings that count to zero, which is when the
native client can leave the guest. Windows games go through Valve's Proton
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

Then take `overlays.default`, which provides the launchers `steam-arm64` and
`steam-arm64-beta`, the client trees `steam-arm64-client` and
`steam-arm64-client-beta` behind them, and `steam-x86`. The client is unfree, so
the consumer sets `nixpkgs.config.allowUnfree = true`. Its `steamui.so` and
`vgui2_s.so` link GTK 2, its tray loads `libappindicator.so.1`, and its
`libavformat.so.58` links Debian's `libbz2.so.1.0`, a soname nixpkgs' bzip2
does not carry. All come from Valve's own aarch64 runtime:
`steam-runtime-arm64-libs` takes Valve's GTK 2 2.24.33, its Ayatana tray
libraries and its bzip2 out of the pinned runtime, so nothing depends on
nixpkgs' `gtk2`, and each runtime update brings Valve's build along. The FHS
gives that package priority, so where nixpkgs ships a file of the same name,
Valve's library is the one the loader finds.
`checks.client-libraries-resolve` reads every library the pinned client and
Valve's libraries ask for and looks each one up the way the FHS's loader does,
in an index `ldconfig` builds from the FHS, keyed by soname. It fails, naming
the library, when the loader cannot find one, when a library taken from
Valve's runtime is no longer needed, and when the loader would serve one of
those from anywhere but Valve's runtime. Each client or runtime update runs it.

## Running without the microVM

By default the launcher starts the client inside a muvm microVM, because
Valve's binaries need 4K pages and Asahi Linux hosts use 16K. On a host whose
kernel already uses 4K pages, or one without `/dev/kvm`, turn the microVM off:

```nix
pkgs.steam-arm64.override { useMuvm = false; }
```

The client then runs straight in its FHS sandbox and muvm is not built. x86
Linux games and x86 Proton need the FEX rootfs and an x86 binfmt handler, which
the microVM sets up itself, so on the host the NixOS module provides them:

```nix
{
  imports = [ inputs.steam-arm64-nix.nixosModules.fex-host ];
  programs.steam-arm64.fexHost.enable = true;
}
```

It mounts the rootfs image at `/run/fex-emu/rootfs` and registers FEX for
x86-64 and i386 binaries, so it needs a kernel with `CONFIG_EROFS_FS` and
`CONFIG_BINFMT_MISC`. The launcher names the graphics provider and the rootfs
when it finds the mount. `steam-arm64 --doctor` reports what is missing.
Without the module, native aarch64 games and Proton (ARM64) still work, and
x86 titles do not. `steam-x86` always uses the microVM.

## Channels

`steam-arm64` pins Valve's stable manifest and leaves the client on stable.
`steam-arm64-beta` pins the publicbeta manifest and opts the client into it at
the first install, by writing `package/beta` in the Steam root. After that the
client owns that file: its own settings switch the channel, and the launcher
never rewrites it. Both clients in the shared root read the same file, so the
x86 client follows the same channel.

### Deck mode

Started with `-steamos3 -steampal -steamdeck -clientbeta steamdeck_publicbeta`
(after `-gamepadui`), the client shows the Deck settings pages, Wi-Fi and
Bluetooth among them. It calls a few SteamOS helper scripts by path, so the FHS
sandbox carries stand-ins for them under `/usr/bin` (`steamos-stubs.nix`): each
answers "nothing to do", and the Wi-Fi backend stays whatever the host runs.
The host still has to provide NetworkManager and BlueZ and let the session
user use them.

`-clientbeta` and `package/beta` must name the same channel or the client keeps
exiting 42. When the arguments carry `-clientbeta`, the launcher writes that
channel to `package/beta` before starting; without it the file stays the
client's. The launcher also stops after five restart requests in a row that
each lasted under a minute, instead of looping forever.

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
arm64, a Proton for ARM64). It also starts the runtime's vulkaninfo the way
Steam starts a game, once in Runtime 4.0 arm64 and once through Valve's FEX
tool in Runtime 2.0, and reports whether each gets the GPU's Vulkan and GL
drivers.

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
| x86 Linux games | works: Valve's FEX tool, the runtime the game names, Vulkan and GL from the FEX rootfs's x86 Mesa, no launch option | works, FEX with Runtime sniper | `steam-arm64 --doctor`: an x86-64 game under FEX gets the GPU's Vulkan and GL drivers |
| aarch64 Linux games | native | not possible | by construction |
| Gamepads | works through muvm's hidpipe, always on: host joysticks recreated by uinput in the guest, rumble included; no hidraw, since the guest kernel has no HID stack, so gyro, touchpad, lightbar and Steam Input's HID drivers are missing (AsahiLinux/muvm#244) | same | `controller.txt`: a DualSense opened in the native client; muvm `hidpipe_server.rs`; libkrunfw's aarch64 config; a guest lists no `/dev/hidraw` |
| Remote Play, Steam Link, LAN transfer | the guest cannot announce itself: passt opens its sockets without broadcast and gives link-local multicast no scope, so the client's UDP broadcast to 27036 and its IPv6 multicast never leave (passt bug 163, open). Both launchers publish UDP 27031 and 27036 and TCP 27036 and 27037, so a LAN device's discovery and stream reach the guest through the host's bound sockets; untested with a device. Pairing by PIN and the same-account host list go through Steam's servers and need no broadcast | same | every launch log; `remote_connections.txt`; passt `udp_flow.c`, `util.c`, `pif.c` |
| In-game overlay | libraries present for aarch64 and, for FEX games, x86-64; attachment under FEX unverified | present | `steamrtarm64/` and `ubuntu12_64/` |
| Game Recording | present, unverified: the logs show it declining a game it is disabled for | same | `console-linux.txt` |
| Big Picture | works | unverified | no run yet for steam 64-bit |
| Audio | works | works | the guest sees `pipewire-0`; `steamui_audio.txt` lists sinks |
| Voice chat, microphone | unverified | unverified | no run yet |
| Screenshots | unverified | unverified | needs the overlay |
| Tray icon, notifications | works over the bridged session bus | works | the launchers' bus checks |
| Network status (Big Picture) | the host's NetworkManager over the bridged system bus | same | `steam-arm64 --doctor`, `client_networkmanager.txt` |
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

`scripts/update.sh [stable|publicbeta]` regenerates `client-sources/<channel>.nix`
from Valve's manifest, which carries each component's sha256; with no argument
it regenerates both channels.

## License

MIT for the packaging in this repository. Valve's client is unfree and is
marked so in the derivation's `meta`.

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
