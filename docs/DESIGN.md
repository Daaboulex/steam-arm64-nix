# Design

Why the packaging is built the way it is. The [README](../README.md) says how to use it.

## Two clients

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

## Where the client's libraries come from

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
program called as `<switch> 4k <command> <args>`. Mainline Linux has none: a
per-program page size was discussed upstream in 2026 only for sizes at or
above the kernel's own. Kernels outside mainline have offered one, such as
omacom's Aurora fork (`ARM64_USER4K_EXPERIMENTAL`, booted with `user4k=on`,
with a `userpages` launcher in its source tree) and Google's P3S in Android's
kernel; neither is reviewed upstream, and this package ships, tests against
and vouches for none of them. It reads no kernel flag: a switch is passed in,
and each launch measures whether it works.

What each package carries follows from the same facts: `steam-arm64-host` and
`steam-x86-host` hold no muvm and no VM rootfs (on 2026-11-11, 3.5 GiB and
1.1 GiB against 5.2 GiB and 2.4 GiB for the guest launchers), and a page switch
enters a closure only when one is passed.

## The NixOS module

`programs.steam-arm64.pageSize` is read from the kernel's configuration
(`ARM64_4K_PAGES`, `ARM64_16K_PAGES` or `ARM64_64K_PAGES`); a kernel that states
none, such as nixpkgs' generic aarch64 kernel, needs it stated with the value
`getconf PAGESIZE` prints, and a value that contradicts the kernel is refused.
On a 4K kernel the module installs the host launchers, with no muvm; on 16K
and 64K kernels it installs the guest launchers, which still run on the host
when `programs.steam-arm64.pageSwitch` names a page switch that gives a
program 4K pages at launch (the module takes any such program and names none;
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
one list in [`ports.nix`](../ports.nix). `checks.module-refusals` evaluates each refusal and
the host and guest wiring.

## The client tree package

`steam-arm64-client`, the flake's default package, is the unpacked client tree;
its entry point is `steamrtarm64/steam`. [`package.nix`](../package.nix) unpacks
Valve's archives and patches nothing: the binaries ask for
`/lib/ld-linux-aarch64.so.1`, so on NixOS the tree does not run by itself. The
`steam-arm64` launchers copy it into a Steam root that holds no client yet and
run it there inside the FHS environment of [`fhs.nix`](../fhs.nix). Valve's
client keeps itself current from the network once it is running.

## Moving and resizing the native client's window

Valve's aarch64 web helper never carves the input shape of the window it
embeds, so presses on the client's own title bar and edges never reach the
window manager: the window's own chrome cannot move or resize it. The x86 web
helper does carve it, and the traces of both clients prove the difference. The
native client runs only Valve's aarch64 helper.
Until Valve's aarch64 helper carries the shape code, KWin moves and resizes the
window as it does any other: Meta with the left button drags it, Meta with the
right button resizes it, and the three title bar buttons work.

Both clients open windows of class `steam`, so only the native client's desktop
entry claims that class and the `steam://` scheme; a second claim would make
the task manager name either client's window after the x86 entry.

## One shared Steam root

Two costs of one shared root, accepted for a fallback client: both packages ship
the x86-64 overlay files under `ubuntu12_64/` and `steamrt64/` at different
sizes, so the first start of either client after the other one ran repairs
those files and restarts once; and pressure-vessel regenerates the locales it
misses at each container start, which is upstream noise.
