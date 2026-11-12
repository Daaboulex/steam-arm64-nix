# Devices

Which way a machine runs the clients follows from its kernel's page size, and
whether it was tried. Read 2026-11-07 from each project's own pages; only the
M1 row and the runner row are verified.

| Device | Kernel pages | Path here | Verified |
|---|---|---|---|
| Apple M1, M2 (Asahi) | 16K | guest; GPU through muvm's native context | yes, the M1 this is developed on |
| Apple M1 and later on a kernel outside mainline with per-program 4K pages | 16K, with 4K per program where the kernel allows it | host through `pageSwitch` when the switch gives 4K pages at launch, guest otherwise | no |
| Apple M3 (Asahi) | 16K | guest; Asahi says not to expect performant 3D yet (2026-09-06), so likely software GPU | no |
| Apple M4 and later | no Asahi kernel | none | no |
| Snapdragon X Elite, X Plus, X13s, SDM845 phones (Pocophone F1, Pixel 3) | 4K on mainline | host: `steam-arm64-host` and `steam-x86-host` with `hostBinfmt`; turnip Vulkan | no |
| Raspberry Pi 5 | 16K with `kernel_2712.img`, 4K with `kernel8.img` | guest with software GPU (v3d has no muvm native context), or host on the 4K kernel | no |
| Raspberry Pi 4 | 4K | host; v3dv Vulkan 1.2 | no |
| RK3588 (Mali-G610, PanVK) | 4K | host | no |
| Pinebook Pro (RK3399) | 4K | host; no Vulkan, so no Proton | no |
| Ampere Altra, One | 4K by default; 64K distro kernels exist | 4K: host; 64K: guest | no; the 64K path is unverified anywhere, muvm on a 64K host has no test on record |
| NVIDIA Grace, DGX Spark (GB10) | 64K | guest; FEX refuses a 64K host | no, unverified |
| Jetson Orin, MediaTek Chromebooks | unconfirmed | host if 4K, guest otherwise | no |
| GitHub `ubuntu-24.04-arm` runner | 4K | host, headless: the Host probe workflow registers FEX, mounts the rootfs and runs both doctors | by dispatching the workflow |
| Steam Frame | SteamOS arm64, Valve's own client and FEX | not a NixOS target | n/a |
