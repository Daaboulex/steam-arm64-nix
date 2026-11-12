# What works

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
| Remote Play, Steam Link, LAN transfer | the guest cannot announce itself: passt opens its sockets without broadcast and gives link-local multicast no scope, so the client's UDP discovery broadcast and its IPv6 multicast never leave. Both launchers publish the ports nixpkgs' `programs.steam` opens, listed in [`ports.nix`](../ports.nix); `programs.steam-arm64.remotePlay.openFirewall` and `localNetworkGameTransfers.openFirewall` open the same sets on the host (the discovery port with either), so a LAN device's discovery, stream and transfer reach the guest through the host's bound sockets; untested with a device. Pairing by PIN and the same-account host list go through Steam's servers and need no broadcast | same | every launch log; `remote_connections.txt`; passt `udp_flow.c`, `util.c`, `pif.c`; `checks.remote-play-ports-published` |
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
