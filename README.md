# Steam for aarch64 (Nix)

Valve's native aarch64 Steam client for NixOS, with Valve's x86_64 client as a
fallback for what the native one cannot run.

It is developed and used daily on an Apple M1 under Asahi. Other aarch64
machines have a path too, but nobody has tried them yet. Valve does not support
Steam for Linux on ARM hardware, so expect rough edges.

## What you get

- `steam-arm64` is the native client. Windows games run through Proton (ARM64),
  x86 Linux games through Valve's own FEX tool.
- `steam-x86` is Valve's x86_64 client, translated by FEX.

Both share one Steam root, so the library, the downloads and the compatibility
tools are the same in each.

## Install

Add the flake:

```nix
{
  inputs.steam-arm64-nix = {
    url = "github:Daaboulex/steam-arm64-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then import the module and switch it on. The client is unfree.

```nix
{
  imports = [ inputs.steam-arm64-nix.nixosModules.default ];
  nixpkgs.overlays = [ inputs.steam-arm64-nix.overlays.default ];
  nixpkgs.config.allowUnfree = true;

  programs.steam-arm64 = {
    enable = true;
    x86.enable = true;
  };
}
```

Start it with `steam-arm64`, or `steam-x86` for the fallback client.

## Will it run on my machine

That depends on the page size of your kernel, because Valve's binaries and FEX
both need 4K pages.

| Kernel pages | Example | How the client runs | Tried |
|---|---|---|---|
| 16K | Apple M1 and M2 under Asahi | inside a small virtual machine (muvm) | yes |
| 4K | Snapdragon X, Raspberry Pi 4, RK3588 | directly on the host, no virtual machine | no |
| 64K | Ampere and NVIDIA server kernels | inside the virtual machine | no |

The module reads the page size from the kernel's configuration. A kernel that
states none needs `programs.steam-arm64.pageSize` set to what
`getconf PAGESIZE` prints.

The full list of devices is in [docs/DEVICES.md](docs/DEVICES.md).

## What works

On the M1, in daily use: the store, library and community pages, downloads,
cloud saves, the workshop, Windows games through Proton, x86 Linux games,
gamepads with rumble, audio, the tray icon and Big Picture.

Known limits:

- The native client's window cannot be moved by its own title bar. Hold Meta
  and drag with the left mouse button to move it, with the right one to resize.
- Inside the virtual machine a gamepad has no gyro, touchpad or lightbar.
- Inside the virtual machine the client cannot announce itself on the network,
  which Remote Play, Steam Link and LAN transfers rely on.
- Android games do not run.
- Voice chat, screenshots and the Deck interface have not been tried.

Every feature, for both clients, with what it was checked against:
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Options you are likely to set

| Option | What it is for |
|---|---|
| `x86.enable` | Install the x86_64 fallback client as well |
| `extraCompatPackages` | Extra compatibility tools for the native client, the same packages `programs.steam` takes |
| `x86.extraCompatPackages` | The same for the x86_64 client |
| `remotePlay.openFirewall` | Open the Remote Play ports on the host |
| `localNetworkGameTransfers.openFirewall` | Open the ports for LAN game transfers |
| `hostBinfmt` | On a 4K kernel, let x86 programs run through FEX, which x86 games and the x86 client need there |

Every option, with its type and default: [docs/OPTIONS.md](docs/OPTIONS.md).

## Beta channel

`steam-arm64-beta` follows Valve's public beta instead of stable. It opts the
client in at the first install. After that the client's own settings switch the
channel, for both clients, since they share one Steam root.

## When something does not work

```bash
steam-arm64 --doctor
steam-x86 --doctor
```

Each reports what a game needs and whether it is there: the page size, FEX,
the graphics drivers, the session bus, the gamepads the client can see and the
Steam components the client must have downloaded.

To keep a log of a run, record it through a terminal. A plain redirect loses
everything the virtual machine prints.

```bash
script -q -c "steam-arm64" steam-arm64.log
```

## More

- [docs/DESIGN.md](docs/DESIGN.md): why a virtual machine, how a launcher
  chooses where to run, where the client's libraries come from
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): building, the checks, updating
  the pinned client

## License

MIT for the packaging in this repository. Valve's client is unfree.
