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
fails the day a client update brings that count to zero. That day is a
decision, not a switch: the client itself could then leave the guest, but
Proton (ARM64) carries FEX, which refuses a non-4K host, so Windows games
would still need the guest on a 16K kernel. Windows games go through Valve's Proton
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
`steam-arm64-client-beta` behind them, and `steam-x86` with its FHS and FEX
bundle, and import `nixosModules.default` (below), which installs the clients
the right way for the kernel's page size. The client is unfree, so
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

## Channels

`steam-arm64` pins Valve's stable manifest and leaves the client on stable.
`steam-arm64-beta` pins the publicbeta manifest and opts the client into it at
the first install, by writing `package/beta` in the Steam root. After that the
client owns that file: its own settings switch the channel, and the launcher
never rewrites it. Both clients in the shared root read the same file, so the
x86 client follows the same channel.

## Running on a 4K-page kernel

Valve's binaries need 4K pages, which is why `steam-arm64` starts the client
in muvm's guest, and FEX needs them too, which is why `steam-x86` does. On an
aarch64 host whose kernel already uses 4K pages the guest is not needed:
`steam-arm64-host` (`pkgs.steam-arm64.override { guest = false; }`) runs the
native client straight in its FHS sandbox, with no muvm, no x86 rootfs and no
FEX interpreter in its closure, and `steam-x86-host`
(`pkgs.steam-x86.override { guest = false; }`) runs the x86 client under the
host's FEX. Both refuse to start on a kernel with any other page size and say
which package to use instead. Native aarch64 games and Proton (ARM64) run this
way; x86 Linux games, x86 Proton and the x86 client itself need the FEX rootfs
and an x86 binfmt handler on the host, which `programs.steam-arm64.hostBinfmt`
sets up.

Every launcher decides at launch, from the running kernel, never from the
build: it reads `getconf PAGESIZE`, runs on the host at 4096, and otherwise
asks the page switch it was built with, if any, to start `getconf` with 4K
pages. Only when that program reports 4096 does the client run on the host
under the switch, which hands the 4K preference to everything Steam starts,
FEX and games included; else it runs in muvm's guest, or the host-only package
refuses. Each launch prints which path it took and why. A page switch is a
program called as `<switch> 4k <command> <args>`; the only kernel with one
today is omacom's Aurora (`ARM64_USER4K_EXPERIMENTAL`, booted with
`user4k=on`), whose `userpages` is packaged by aurora-linux-nixos. This package
reads no kernel flag for it: the switch is passed in, and the launch measures
whether it works.

What each package carries follows from the same facts: `steam-arm64-host` and
`steam-x86-host` hold no muvm and no VM rootfs (on 2026-11-11, 3.5 GiB and
1.1 GiB against 5.2 GiB and 2.4 GiB for the guest launchers), and a page switch
enters a closure only when one is passed.

## NixOS module

```nix
{
  imports = [ inputs.steam-arm64-nix.nixosModules.default ];
  nixpkgs.overlays = [ inputs.steam-arm64-nix.overlays.default ];

  programs.steam-arm64 = {
    enable = true;
    x86.enable = true;
    extraCompatPackages = [ pkgs.proton-ge ];
  };
}
```

`programs.steam-arm64.pageSize` is read from the kernel's configuration
(`ARM64_4K_PAGES`, `ARM64_16K_PAGES` or `ARM64_64K_PAGES`); a kernel that states
none, such as nixpkgs' generic aarch64 kernel, needs it stated with the value
`getconf PAGESIZE` prints, and a value that contradicts the kernel is refused.
On a 4K kernel the module installs the host launchers, with no muvm; on 16K
and 64K kernels it installs the guest launchers, which still run on the host
when `programs.steam-arm64.pageSwitch` names a page switch that gives a
program 4K pages at launch (set it to aurora-linux-nixos's
`packages.<system>.userpages` with an Aurora kernel booted with `user4k=on`;
it is refused on a 4K kernel, where it would never be asked). `hostBinfmt = true` registers FEX as the x86-64 and
i386 binfmt handler (`FEX-x86_64` and `FEX-i386`, opened at registration so
x86 binaries run inside pressure-vessel's containers), mounts the FEX rootfs
at `/run/fex-emu/rootfs` and sets `FEX_ROOTFS` for every session, which the x86
client needs on a 4K kernel and with a page switch. `hostBinfmt` is refused off
4K without a page switch, where FEX cannot run, and beside another handler for
the same ELF magic, such as `boot.binfmt.emulatedSystems = [ "x86_64-linux" ]`.
With a page switch, an x86 binary started outside Steam has no 4K preference
and FEX refuses it.
`extraCompatPackages` takes the same tool packages `programs.steam` does, for
the native client; `x86.extraCompatPackages` takes x86-64 tools for the x86
client, built as aarch64 derivations (a prebuilt tarball runs nothing at
build time). `remotePlay.openFirewall` and `localNetworkGameTransfers.openFirewall`
open on the host the ports both launchers publish out of the guest, from the
one list in `ports.nix`. `checks.module-refusals` evaluates each refusal and
the host and guest wiring.

## Devices

Which way a machine runs the clients follows from its kernel's page size, and
whether it was tried. Read 2026-11-07 from each project's own pages; only the
M1 row and the runner row are verified.

| Device | Kernel pages | Path here | Verified |
|---|---|---|---|
| Apple M1, M2 (Asahi) | 16K | guest; GPU through muvm's native context (Asahi 7.1.5's regression fixed 2026-09-11) | yes, the M1 this is developed on |
| Apple M1 and later on omacom's Aurora kernel, booted with `user4k=on` | 16K, with 4K per program | host through `pageSwitch` (Aurora's `userpages`), guest when the switch refuses | no; the contributor of PR 8 reports `userpages 4k steam` running on it, before this package had the path |
| Apple M3 (Asahi) | 16K | guest; Asahi says not to expect performant 3D yet (2026-09-06), so likely software GPU | no |
| Apple M4 and later | no Asahi kernel | none | no |
| Snapdragon X Elite, X Plus, X13s, SDM845 phones (Pocophone F1, Pixel 3) | 4K on mainline | host: `steam-arm64-host` and `steam-x86-host` with `hostBinfmt`; turnip Vulkan | the contributor's report in his PR #6 comment of 2026-11-07: on his Pocophone F1 everything works, the x86-64 runtime runs well and so does ARM64 Proton, with PR #6's host path; a report, not a doctor transcript, and this module's build has not run there |
| Raspberry Pi 5 | 16K with `kernel_2712.img`, 4K with `kernel8.img` | guest with software GPU (v3d has no muvm native context), or host on the 4K kernel | no |
| Raspberry Pi 4 | 4K | host; v3dv Vulkan 1.2 | no |
| RK3588 (Mali-G610, PanVK) | 4K | host | no |
| Pinebook Pro (RK3399) | 4K | host; no Vulkan, so no Proton | no |
| Ampere Altra, One | 4K by default; 64K distro kernels exist | 4K: host; 64K: guest | no; the 64K path is unverified anywhere, muvm on a 64K host has no test on record |
| NVIDIA Grace, DGX Spark (GB10) | 64K | guest; FEX refuses a 64K host | no, unverified |
| Jetson Orin, MediaTek Chromebooks | unconfirmed | host if 4K, guest otherwise | no |
| GitHub `ubuntu-24.04-arm` runner | 4K | host, headless: the Host probe workflow registers FEX, mounts the rootfs and runs both doctors | by dispatching the workflow |
| Steam Frame | SteamOS arm64, Valve's own client and FEX | not a NixOS target | n/a |

## Usage

The package is the unpacked client tree; its entry point is `steamrtarm64/steam`.
The binaries are unpatched and ask for `/lib/ld-linux-aarch64.so.1`, so running
them needs `programs.nix-ld.enable` or an FHS environment. Valve's client keeps
itself current from the network once it is running.

## Development

```bash
nix build .#packages.aarch64-linux.default
nix flake check --no-eval-cache
```

The checks that cannot run on this 16K machine run on GitHub's 4K-page
`ubuntu-24.04-arm` runner: the Host probe workflow (`workflow_dispatch` only)
runs `packages.host-probe`, which registers the module's two FEX handlers and
mounts its rootfs as root, proves an x86-64 binary runs through them, and runs
`steam-arm64 --doctor` from the `steam-arm64-host` package and
`steam-x86 --doctor` from `steam-x86-host`, headless. It cannot prove a window,
the GPU or Deck mode.

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
steam-x86 --doctor
```

Each runs inside the sandbox its client gets, in the guest (joining a running
client or starting a guest of its own) or on the host, and reports each thing
an x86 game needs: the 4K page size, the binfmt handler, the FEX rootfs and
the graphics provider, python3 for Valve's FEX tool, the cursor path, the
session bus, the SteamOS helpers Deck mode calls, and the Steam apps the
client must have downloaded (FEX, Steam Linux Runtime 4.0 arm64, a Proton for
ARM64). The native doctor also starts the runtime's vulkaninfo the way Steam
starts a game, once in Runtime 4.0 arm64 and once through Valve's FEX tool in
Runtime 2.0, and reports whether each gets the GPU's Vulkan and GL drivers,
and counts the gamepads and hidraw devices the client can see.

Extra compatibility tools reach a client through `STEAM_EXTRA_COMPAT_TOOLS_PATHS`,
the variable nixpkgs' `programs.steam.extraCompatPackages` sets. The module's
`extraCompatPackages` and `x86.extraCompatPackages` set it per client through
each launcher's `extraCompatTools` argument, ahead of whatever the session
already names, and a package without a `compatibilitytool.vdf` fails the
launcher's build.

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
| Gamepads | works through muvm's hidpipe, always on: host joysticks recreated by uinput in the guest, rumble included; no hidraw, since the guest kernel has no HID stack, so gyro, touchpad, lightbar and Steam Input's HID drivers are missing (AsahiLinux/muvm#244); on the host path hidraw is there once `hardware.steam-hardware.enable` grants it, and the doctor counts the devices | same | `controller.txt`: a DualSense opened in the native client; muvm `hidpipe_server.rs`; libkrunfw's aarch64 config; `steam-arm64 --doctor`'s hidraw line |
| Remote Play, Steam Link, LAN transfer | the guest cannot announce itself: passt opens its sockets without broadcast and gives link-local multicast no scope, so the client's UDP broadcast to 27036 and its IPv6 multicast never leave. Both launchers publish the ports nixpkgs' `programs.steam` opens, from `ports.nix`: UDP 27031 to 27036 and 10400 to 10401, TCP 27036, 27037 and 27040; `programs.steam-arm64.remotePlay.openFirewall` and `localNetworkGameTransfers.openFirewall` open the same sets on the host (the discovery port UDP 27036 with either), so a LAN device's discovery, stream and transfer reach the guest through the host's bound sockets; untested with a device. Pairing by PIN and the same-account host list go through Steam's servers and need no broadcast | same | every launch log; `remote_connections.txt`; passt `udp_flow.c`, `util.c`, `pif.c`; `checks.remote-play-ports-published` |
| Running on the host, no microVM | on a 4K kernel, or on a larger one whose page switch gives a launched program 4096-byte pages, both measured at each launch; `steam-arm64-host` refuses any other kernel and names the guest launcher; the switch path is untested on hardware | `steam-x86-host`: Valve's x86 client under the host's FEX, with `hostBinfmt`, by the same choice | `checks.launcher-chooses-a-path`, `checks.steam-arm64-host-wiring`, `checks.module-refusals`; the Host probe on the 4K runner |
| Deck UI (`-gamepadui -steamos3 -steampal -steamdeck`) | the SteamOS helpers the client calls are stood in: an update check answers no update, the branch list is `rel` and a switch is refused, Power to desktop shuts the client down; no gamescope session here; the UI itself unverified | the same helpers in the x86 FHS, unverified | `checks.steamos-stubs`; the helper names in `steamui.so`, `steamclient.so` and `steam` |
| Restart after a self-update | the client exits 42 and the launcher runs it again; five requests in a row that each lasted under a minute stop it | Valve's `steam.sh` in the x86 bootstrap restarts on 42 itself (`MAGIC_RESTART_EXITCODE`) | `checks.launcher-restart-loop`; `steam.sh` in `bootstraplinux_ubuntu12_32.tar.xz` |
| Compatibility tools from Nix | `programs.steam-arm64.extraCompatPackages`, the aarch64 builds of GE-Proton and Proton-CachyOS | `x86.extraCompatPackages`, x86-64 builds as aarch64 derivations; the Proton repos ship those for x86_64-linux only today, so Valve's own Protons for now | `checks.steam-arm64-compat-tools`; `compat_log.txt` |
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

Valve closed steam-for-linux#13745, the request to run its aarch64 client on a
16K-page kernel, as not planned on 2026-10-16, and its support page says the
Steam for Linux client is not supported on ARM hardware (read 2026-11-07); no
release note names the desktop arm64 client. What Valve documents is the
mechanism the client uses: the Steam Linux Runtime 4.0 arm64
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
