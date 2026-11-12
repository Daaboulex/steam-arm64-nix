# Development

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

## Updates

[`scripts/update.sh`](../scripts/update.sh) regenerates `client-sources/<channel>.nix`
from Valve's manifest, which carries each component's sha256. It takes `stable`
or `publicbeta`, and with no argument it regenerates both channels.
