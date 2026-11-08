{
  description = "Valve's aarch64 Steam client packaged for NixOS - pinned from Valve's own client manifest";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard/release";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-linux" ];

      imports = [ inputs.std.flakeModules.base ];

      perSystem =
        {
          system,
          self',
          lib,
          ...
        }:
        let
          consumerConfig = {
            allowUnfree = true;
          };
          pkgs = import inputs.nixpkgs {
            inherit system;
            config = consumerConfig;
          };
          muvm = pkgs.callPackage ./muvm-patched.nix { inherit (self'.packages) fex-interpreter; };
        in
        {
          packages.steam-arm64-client = pkgs.callPackage ./package.nix { channel = "stable"; };
          packages.steam-arm64-client-beta = pkgs.callPackage ./package.nix { channel = "publicbeta"; };
          packages.default = self'.packages.steam-arm64-client;
          packages.steam-runtime-arm64 = pkgs.callPackage ./runtime.nix { };
          packages.steam-runtime-arm64-libs = pkgs.callPackage ./runtime-libs.nix {
            inherit (self'.packages) steam-runtime-arm64;
          };
          packages.steam-arm64-fhs = pkgs.callPackage ./fhs.nix {
            inherit (self'.packages) steam-runtime-arm64;
            inherit (self'.packages) steam-runtime-arm64-libs;
          };
          packages.steam-x86-rootfs = pkgs.callPackage ./fex-rootfs-x86.nix { };
          packages.fex-interpreter = pkgs.callPackage ./fex-interpreter.nix { };
          packages.fex-emulator-x86 = pkgs.callPackage ./fex-emulator-x86.nix { };
          packages.steam-x86-fhs = pkgs.callPackage ./fhs-x86.nix {
            steam-x86-entry = pkgs.steam-unwrapped;
            inherit (self'.packages) fex-emulator-x86 fex-interpreter;
          };
          packages.steam-x86 = pkgs.callPackage ./launcher-x86.nix {
            inherit muvm;
            inherit (self'.packages) steam-x86-rootfs steam-x86-fhs fex-emulator-x86;
          };

          packages.steam-arm64 = pkgs.callPackage ./launcher.nix {
            inherit muvm;
            channel = "stable";
            inherit (self'.packages) steam-arm64-client steam-arm64-fhs steam-x86-rootfs;
          };
          packages.steam-arm64-beta = pkgs.callPackage ./launcher.nix {
            inherit muvm;
            channel = "publicbeta";
            steam-arm64-client = self'.packages.steam-arm64-client-beta;
            inherit (self'.packages) steam-arm64-fhs steam-x86-rootfs;
          };
          packages.steam-arm64-host = self'.packages.steam-arm64.override { guest = false; };
          packages.steam-x86-host = self'.packages.steam-x86.override { guest = false; };

          pre-commit.settings.hooks = {
            trim-trailing-whitespace.excludes = [ "\\.patch$" ];
            end-of-file-fixer.excludes = [ "\\.patch$" ];
            typos.excludes = [ "\\.patch$" ];
            typos.settings.config.default.extend-words.passt = "passt";
          };

          checks.muvm-patches-apply =
            pkgs.runCommand "muvm-patches-apply" { nativeBuildInputs = [ pkgs.gnupatch ]; }
              ''
                cp -r ${muvm.src} src
                chmod -R +w src
                cd src
                patch -p1 <${./muvm-mask-mit-shm.patch}
                patch -p1 <${./muvm-bridge-dbus.patch}
                patch -p1 <${./muvm-vm-tuning.patch}
                patch -p1 <${./muvm-guest-groups.patch}
                patch -p1 <${./muvm-guest-dns.patch}
                patch -p1 <${./muvm-bridge-system-bus.patch}
                touch "$out"
              '';

          checks.fex-interpreter-still-needed = pkgs.runCommand "fex-interpreter-still-needed" { } ''
            if ! grep -qF 'find_in_path("FEXInterpreter")' ${pkgs.muvm.src}/crates/muvm/src/guest/fex.rs; then
              echo "muvm ${pkgs.muvm.version} no longer looks up FEXInterpreter on the guest's PATH."
              echo "Read guest/fex.rs. If it finds FEX by the name FEX ${pkgs.fex.version} installs,"
              echo "delete fex-interpreter.nix, the wrapProgram in muvm-patched.nix, the alias in"
              echo "guest-run-x86.sh and fhs-x86.nix (exec FEX itself there), and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-session-bus-divergence = pkgs.runCommand "muvm-session-bus-divergence" { } ''
            if grep -rqE 'DBUS_SOCKET|join\("bus"\)|DBUS_SESSION_BUS_ADDRESS' ${pkgs.muvm.src}/crates/muvm/src; then
              echo "muvm ${pkgs.muvm.version} now names the session bus itself."
              echo "Read what it does. If the tray in the guest gets its menu over the"
              echo "desktop's bus without our patch, delete muvm-bridge-dbus.patch, its lines"
              echo "in muvm-patched.nix and muvm-patches-apply, and this check; the fallback"
              echo "bus in both guest-run scripts stays for a session without a bus."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-stdin-divergence = pkgs.runCommand "muvm-stdin-divergence" { } ''
            if ! grep -qF 'epoll.add(stdin.as_fd()' ${pkgs.muvm.src}/crates/muvm/src/tty.rs; then
              echo "muvm ${pkgs.muvm.version} no longer adds its stdin to epoll in tty.rs, the"
              echo "line that fails with EPERM on /dev/null and a regular file."
              echo "Launch into a running guest from a desktop entry. If the launch lands,"
              echo "delete stdin_as_pipe in both launchers, join-stdin-epollable, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-lock-name-divergence = pkgs.runCommand "muvm-lock-name-divergence" { } ''
            if ! grep -qF 'join("muvm.lock")' ${pkgs.muvm.src}/crates/muvm/src/launch.rs; then
              echo "muvm ${pkgs.muvm.version} no longer names its lock file muvm.lock in launch.rs."
              echo "Both launchers flock that file to learn whether a guest is running: a guest"
              echo "numbers its processes from one, so the pid file the last client left names"
              echo "a live process in the next guest and the client exits believing it already"
              echo "runs; with no guest holding the lock the pid file is stale and is removed."
              echo "Find the new name and set it in forget_stale_pid in both launchers and here."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-system-bus-divergence = pkgs.runCommand "muvm-system-bus-divergence" { } ''
            if grep -rq system_bus_socket ${pkgs.muvm.src}/crates/muvm/src; then
              echo "muvm ${pkgs.muvm.version} now names the system bus socket itself."
              echo "Read what it does. If the guest reaches the host's system bus, delete"
              echo "muvm-bridge-system-bus.patch, the DBUS_SYSTEM_BUS_ADDRESS lines in both"
              echo "guest-run scripts, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-shm-divergence = pkgs.runCommand "muvm-shm-divergence" { } ''
            if grep -q MIT-SHM ${pkgs.muvm.src}/crates/muvm/src/guest/bridge/x11.rs; then
              echo "muvm ${pkgs.muvm.version} now names MIT-SHM in its own X11 bridge."
              echo "Read what it does there. If it masks or proxies the extension,"
              echo "delete muvm-mask-mit-shm.patch, its override in launcher.nix, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-groups-divergence = pkgs.runCommand "muvm-groups-divergence" { } ''
            if grep -q setgroups ${pkgs.muvm.src}/crates/muvm/src/guest/user.rs; then
              echo "muvm ${pkgs.muvm.version} now sets the supplementary groups itself."
              echo "Read what it claims. If the command in the vm ends up in the host's"
              echo "input group, delete muvm-guest-groups.patch, its line in"
              echo "muvm-patched.nix and in muvm-patches-apply, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-memory-divergence = pkgs.runCommand "muvm-memory-divergence" { } ''
            src=${pkgs.muvm.src}/crates/muvm/src
            if [ ! -d "$src" ]; then
              echo "muvm ${pkgs.muvm.version} has no $src; find where the guest init lives now."
              exit 1
            fi
            if grep -rqE 'page_reporting_order|compaction_proactiveness' "$src"; then
              echo "muvm ${pkgs.muvm.version} now tunes the guest's page reporting or compaction itself."
              echo "Read what it sets. If freed guest memory reaches the host without our values,"
              echo "drop RETURN_FREED_MEMORY_TO_HOST from muvm-vm-tuning.patch and delete this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-dns-divergence = pkgs.runCommand "muvm-dns-divergence" { } ''
            src=${pkgs.muvm.src}/crates/muvm/src/guest
            if [ ! -d "$src" ]; then
              echo "muvm ${pkgs.muvm.version} has no $src; find where the guest init lives now."
              exit 1
            fi
            if grep -rq stub-resolv "$src"; then
              echo "muvm ${pkgs.muvm.version} now names stub-resolv in its guest code."
              echo "Inside the vm, check that getent hosts resolves a name without muvm-guest-dns.patch."
              echo "If it does, delete that patch, its line in muvm-patched.nix and in muvm-patches-apply,"
              echo "and this check."
              exit 1
            fi
            mentions=$(grep -rho resolv "$src" | wc -l)
            if [ "$mentions" -ne 11 ]; then
              echo "muvm ${pkgs.muvm.version} changed how the guest writes resolv.conf ($mentions mentions, was 11)."
              echo "Inside the vm, check that getent hosts resolves a name without muvm-guest-dns.patch."
              echo "If it does, delete that patch, its line in muvm-patched.nix and in muvm-patches-apply,"
              echo "and this check; if not, set the expected count to $mentions."
              exit 1
            fi
            touch "$out"
          '';

          checks.client-libraries-resolve =
            let
              client = self'.packages.default;
              runtimeLibs = self'.packages.steam-runtime-arm64-libs;
            in
            pkgs.runCommand "steam-arm64-client-libraries-resolve"
              {
                nativeBuildInputs = [
                  pkgs.binutils-unwrapped
                  pkgs.glibc.bin
                ];
              }
              ''
                rootfs=${self'.packages.steam-arm64-fhs.fhsenv}
                test -d "$rootfs"
                : > needed
                if grep -aqF libappindicator.so.1 ${client}/steamrtarm64/steamui.so; then
                  printf '%s\n' libappindicator.so.1 >> needed
                fi
                ldconfig -X -C ld.so.cache -f /dev/null "$rootfs/usr/lib64" "$rootfs/usr/lib"
                ldconfig -C ld.so.cache -p > cache
                sed -n 's/^[[:space:]]*\([^[:space:]]*\) (.*=> \(.*\)$/\1 \2/p' cache > index
                test -s index
                cut -d' ' -f1 index > provided
                find ${client} -type f -name '*.so*' -printf '%f\n' >> provided
                find ${client} -type f \( -name '*.so*' -o -perm -u+x \) > files
                while IFS= read -r f; do
                  if readelf -h "$f" >/dev/null 2>&1; then
                    readelf -d "$f" > dynamic
                    sed -n 's/.*Library soname: \[\(.*\)\]/\1/p' dynamic >> provided
                    sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' dynamic >> needed
                  fi
                done < files
                find ${runtimeLibs}/lib -name '*.so*' > runtime-files
                while IFS= read -r f; do
                  readelf -d "$f" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' >> needed
                done < runtime-files
                sort -u needed > needed.sorted
                sort -u provided > provided.sorted
                comm -23 needed.sorted provided.sorted > missing
                if [ -s missing ]; then
                  echo "Valve's aarch64 client asks for libraries the loader in its FHS cannot find:"
                  cat missing
                  echo "Add each to fhs.nix from nixpkgs, or to runtime-libs.nix when only Valve's runtime carries that soname."
                  exit 1
                fi
                status=0
                for soname in ${pkgs.lib.escapeShellArgs runtimeLibs.sonames}; do
                  if ! grep -qxF "$soname" needed.sorted; then
                    echo "runtime-libs.nix carries $soname, which neither the client nor Valve's other libraries need any more: drop it."
                    status=1
                    continue
                  fi
                  served=$(awk -v s="$soname" '$1 == s { print $2; exit }' index)
                  if [ -z "$served" ]; then
                    echo "The FHS loader has no $soname in its index, though runtime-libs.nix carries it."
                    status=1
                    continue
                  fi
                  case "$(readlink -f "$served")" in
                  ${runtimeLibs}/* | ${self'.packages.steam-runtime-arm64}/*) ;;
                  *)
                    echo "The FHS loader serves $soname from $(readlink -f "$served"), not from Valve's runtime: the priority runtime-libs.nix has in fhs.nix no longer wins."
                    status=1
                    ;;
                  esac
                done
                if [ "$status" -ne 0 ]; then
                  exit 1
                fi
                echo "OK: all $(wc -l < needed.sorted) libraries Valve's client asks for resolve in its FHS, and each one taken from Valve's runtime is still needed and served from it"
                touch "$out"
              '';

          checks.client-needs-4k-pages =
            pkgs.runCommand "steam-arm64-client-needs-4k-pages"
              { nativeBuildInputs = [ pkgs.binutils-unwrapped ]; }
              ''
                find ${self'.packages.default} -type f \( -name '*.so*' -o -perm -u+x \) > files
                count=0
                while IFS= read -r f; do
                  if readelf -h "$f" >/dev/null 2>&1; then
                    readelf -lW "$f" > segments
                    if awk '$1 == "LOAD" && strtonum($NF) < 16384 { low = 1 } END { exit !low }' segments; then
                      count=$((count + 1))
                    fi
                  fi
                done < files
                if [ "$count" -eq 0 ]; then
                  echo "Every ELF file in Valve's aarch64 client now has LOAD segments aligned to 16K or more, so it loads on a 16K-page kernel."
                  echo "The native client no longer needs muvm's 4K guest: run it on the host and retire the guest for it."
                  exit 1
                fi
                echo "Valve's aarch64 client still has $count ELF files with LOAD segments aligned below 16K, so it needs muvm's 4K guest"
                touch "$out"
              '';

          checks.runtime-tools = pkgs.runCommand "steam-arm64-runtime-tools" { } ''
            test -x ${self'.packages.steam-runtime-arm64}/bin/steam-runtime-launcher-service
            test -d ${self'.packages.steam-runtime-arm64}/pressure-vessel
            rootfs=${self'.packages.steam-arm64-fhs.fhsenv}
            test -d "$rootfs"
            grep -q '${self'.packages.steam-runtime-arm64}/bin' "$rootfs/etc/profile"
            test -e "$rootfs/usr/bin/fusermount3"
            touch "$out"
          '';

          checks.overlay-resolves =
            let
              overlaid = import inputs.nixpkgs {
                inherit system;
                config = consumerConfig;
                overlays = [ inputs.self.overlays.default ];
              };
            in
            pkgs.runCommand "steam-arm64-overlay-resolves" { } ''
              test -x ${overlaid.steam-arm64}/bin/steam-arm64
              test -x ${overlaid.steam-arm64-beta}/bin/steam-arm64
              test -x ${overlaid.steam-arm64-fhs}/bin/steam-arm64-fhs
              touch "$out"
            '';

          checks.cursor-path-forwarded = pkgs.runCommand "steam-cursor-path-forwarded" { } ''
            status=0
            for l in ${./launcher.sh} ${./launcher-x86.sh}; do
              if ! grep -q 'XCURSOR_PATH' "$l"; then
                echo "$l does not hand XCURSOR_PATH to the guest"
                status=1
              fi
            done
            if [ "$status" -ne 0 ]; then
              echo "libXcursor here searches only the home directory and its own empty share"
              echo "directory, so the theme the desktop names resolves in the guest only through"
              echo "the XCURSOR_PATH the session publishes; without it every lookup falls to the"
              echo "X server's built-in bitmap, 10x16 pixels whatever the display scale."
              exit 1
            fi
            touch "$out"
          '';

          checks.one-entry-owns-the-window-class =
            pkgs.runCommand "steam-one-entry-owns-the-window-class" { }
              ''
                grep -q 'startupWMClass = "steam"' ${./launcher.nix} \
                  || {
                    echo "the native client's desktop entry must claim the window class steam"
                    exit 1
                  }
                if grep -q -E 'startupWMClass|mimeTypes' ${./launcher-x86.nix}; then
                  echo "the x86 client's desktop entry must not claim the window class or the"
                  echo "steam URL scheme: both clients open windows of class steam, and a second"
                  echo "claim makes the task manager name the native client's window after it"
                  exit 1
                fi
                touch "$out"
              '';

          checks.remote-play-ports-published = pkgs.runCommand "steam-remote-play-ports-published" { } ''
            for l in ${./launcher.sh} ${./launcher-x86.sh}; do
              for p in 27031:27031/udp 27036:27036/udp 27036:27036 27037:27037; do
                if ! grep -q -- "-p $p" "$l"; then
                  echo "$l no longer publishes $p: passt cannot carry the guest's own LAN"
                  echo "broadcast, so a Steam Link or Remote Play client on the LAN finds this"
                  echo "client only through the published discovery and stream ports"
                  exit 1
                fi
              done
            done
            touch "$out"
          '';

          checks.join-stdin-epollable = pkgs.runCommand "steam-join-stdin-epollable" { } ''
            status=0
            for l in ${./launcher.sh} ${./launcher-x86.sh}; do
              if ! grep -qF 'exec < <(:)' "$l"; then
                echo "$l hands muvm a stdin it may not be able to watch"
                status=1
              fi
            done
            if [ "$status" -ne 0 ]; then
              echo "muvm's io loop for a launch into a running guest adds its stdin to epoll,"
              echo "which fails with EPERM on /dev/null or a regular file after the request was"
              echo "already sent; a desktop entry or a steam:// link launches with exactly that"
              echo "stdin. Replace it with a pipe at end of file before calling muvm."
              exit 1
            fi
            touch "$out"
          '';

          checks.steam-arm64-x86-games-wiring = pkgs.runCommand "steam-arm64-x86-games-wiring" { } ''
            l=${self'.packages.steam-arm64}/bin/steam-arm64
            grep -q -- '-f "${self'.packages.steam-x86-rootfs}"' "$l" \
              || {
                echo "the native client's guest has no FEX rootfs, so no graphics provider"
                exit 1
              }
            grep -q 'STEAM_COMPAT_GRAPHICS_PROVIDER=/run/fex-emu/rootfs/graphics_provider.json' "$l" \
              || {
                echo "the native client does not name the graphics provider for Valve's FEX tool"
                exit 1
              }
            grep -qF '${lib.getExe muvm}' "$l" \
              || {
                echo "the native client's launcher does not start the muvm whose PATH carries FEXInterpreter"
                exit 1
              }
            rootfs=${self'.packages.steam-arm64-fhs.fhsenv}
            test -d "$rootfs"
            test -x "$rootfs/usr/bin/python3" \
              || {
                echo "Valve's fex-compat-tool is a python3 script run outside the container;"
                echo "without python3 in the FHS every x86 tool and game exits at once"
                exit 1
              }
            touch "$out"
          '';

          checks.fex-emulator-x86-self-contained =
            pkgs.runCommand "fex-emulator-x86-self-contained" { nativeBuildInputs = [ pkgs.patchelf ]; }
              ''
                b=${self'.packages.fex-emulator-x86}
                test -f "$b/emulator.json"
                interp=$(patchelf --print-interpreter "$b/bin/FEX")
                case "$interp" in
                "$b/lib/"*) ;;
                *)
                  echo "FEX interpreter escapes the bundle: $interp"
                  exit 1
                  ;;
                esac
                rpath=$(patchelf --print-rpath "$b/bin/FEX")
                case "$rpath" in
                "$b/lib"*) ;;
                *)
                  echo "FEX rpath escapes the bundle: $rpath"
                  exit 1
                  ;;
                esac
                touch "$out"
              '';

          checks.fex-multiblock-divergence = pkgs.runCommand "fex-multiblock-divergence" { } ''
            case "${pkgs.fex.version}" in
            2608*) touch "$out" ;;
            *)
              echo "FEX is at ${pkgs.fex.version}, past 2608. PR #5856 (the dynamic L1"
              echo "cache fix behind FEX issue #5336) landed after 2608, so a newer FEX"
              echo "may make the web-helper Multiblock:0 workaround unnecessary. Re-test"
              echo "the web helper without it, then drop the Config.Multiblock block in"
              echo "fex-emulator-x86.nix and this check if it stays stable."
              exit 1
              ;;
            esac
          '';

          checks.fex-launcher-env = pkgs.runCommand "fex-launcher-env" { } ''
            known=$(grep -aoE 'FEX_[A-Z0-9_]+' ${pkgs.fex}/bin/FEX | sort -u)
            status=0
            for f in ${./launcher.sh} ${./launcher-x86.sh} ${./guest-run-x86.sh}; do
              for v in $(grep -aoE 'FEX_[A-Z0-9_]+' "$f" | sort -u); do
                if ! grep -qxF "$v" <<<"$known"; then
                  echo "$v is set by a launcher but FEX ${pkgs.fex.version} does not name it (a silent no-op)"
                  status=1
                fi
              done
            done
            if [ "$status" -ne 0 ]; then exit 1; fi
            touch "$out"
          '';

          checks.steam-x86-fhs-coreutils = pkgs.runCommand "steam-x86-fhs-coreutils" { } ''
            rootfs=${self'.packages.steam-x86-fhs.fhsenv}
            test -d "$rootfs"
            test -e "$rootfs/usr/bin/true"
            touch "$out"
          '';

          checks.steam-x86-rootfs-erofs = pkgs.runCommand "steam-x86-rootfs-erofs" { } ''
            test "$(od -An -tx1 -j1024 -N4 ${self'.packages.steam-x86-rootfs} | tr -d ' ')" = "e2e1f5e0" \
              || {
                echo "not an EROFS image: ${self'.packages.steam-x86-rootfs}"
                exit 1
              }
            touch "$out"
          '';

          checks.steam-x86-launcher-wiring = pkgs.runCommand "steam-x86-launcher-wiring" { } ''
            l=${self'.packages.steam-x86}/bin/steam-x86
            grep -q '${self'.packages.fex-emulator-x86}/emulator.json' "$l" \
              || {
                echo "launcher does not set the emulator descriptor"
                exit 1
              }
            grep -q '${self'.packages.steam-x86-rootfs}' "$l" \
              || {
                echo "launcher does not mount the rootfs"
                exit 1
              }
            grep -q '${self'.packages.steam-x86-fhs}/bin/steam-x86-fhs' "$l" \
              || {
                echo "launcher does not enter the FHS"
                exit 1
              }
            grep -q 'FEX_ROOTFS=/run/fex-emu/rootfs' ${./guest-run-x86.sh} \
              || {
                echo "guest-run does not set FEX_ROOTFS"
                exit 1
              }
            touch "$out"
          '';

          checks.muvm-guest-path = pkgs.runCommand "muvm-guest-path" { } ''
            wrapper=${lib.getExe muvm}
            for needed in ${pkgs.socat}/bin ${self'.packages.fex-interpreter}/bin; do
              grep -qaF -- "$needed" "$wrapper" "$(dirname "$wrapper")"/.muvm-wrapped* || {
                echo "the muvm wrapper's PATH prefix lost $needed."
                echo "muvm forwards the PATH it runs with into the guest (env.rs). There its"
                echo "init runs socat for the pulse and session bus proxies, and setup_socket_proxy"
                echo "returns Ok without a word when socat is absent, so the tray falls back to"
                echo "an XEmbed icon with no name and no menu; and it registers the x86 binfmt by"
                echo "finding FEXInterpreter, a name FEX no longer installs, so without the alias"
                echo "no x86 game starts. nixpkgs' wrapper carries socat; muvm-patched.nix adds"
                echo "the alias."
                exit 1
              }
            done
            for l in ${self'.packages.steam-arm64}/bin/steam-arm64 \
              ${self'.packages.steam-x86}/bin/steam-x86; do
              if grep -q '"PATH=' "$l"; then
                echo "$l sets the guest's PATH itself, which replaces the one muvm forwards"
                echo "and so drops socat and FEXInterpreter from it. Leave the guest PATH alone."
                exit 1
              fi
            done
            touch "$out"
          '';

          checks.steam-arm64-host-wiring =
            let
              getconf = lib.getExe' pkgs.glibc "getconf";
              hosts = {
                steam-arm64 = {
                  launcher = "${self'.packages.steam-arm64-host}/bin/steam-arm64";
                  closure = pkgs.closureInfo { rootPaths = [ self'.packages.steam-arm64-host ]; };
                  guestOnly = "-muvm- -steam-x86-fedora-rootfs -fex-interpreter";
                  wanted = [
                    "STEAM_COMPAT_GRAPHICS_PROVIDER=/run/fex-emu/rootfs/graphics_provider.json"
                    "${self'.packages.steam-arm64-fhs}/bin/steam-arm64-fhs"
                  ];
                };
                steam-x86 = {
                  launcher = "${self'.packages.steam-x86-host}/bin/steam-x86";
                  closure = pkgs.closureInfo { rootPaths = [ self'.packages.steam-x86-host ]; };
                  guestOnly = "-muvm- -steam-x86-fedora-rootfs";
                  wanted = [
                    "PRESSURE_VESSEL_EMULATOR=\"${self'.packages.fex-emulator-x86}/emulator.json\""
                    "${self'.packages.steam-x86-fhs}/bin/steam-x86-fhs"
                  ];
                };
              };
            in
            pkgs.runCommand "steam-arm64-host-wiring" { } (
              lib.concatStrings (
                lib.mapAttrsToList (name: host: ''
                  for leaves in ${host.guestOnly}; do
                    if grep -qF -- "$leaves" ${host.closure}/store-paths; then
                      echo "the ${name} host launcher still carries $leaves, which only muvm's guest uses"
                      exit 1
                    fi
                  done
                  l=${host.launcher}
                  for wanted in ${
                    lib.escapeShellArgs (
                      host.wanted
                      ++ [
                        "\"${getconf}\" PAGESIZE"
                        "MESA_SHADER_CACHE_MAX_SIZE=50G"
                      ]
                    )
                  }; do
                    grep -qF -- "$wanted" "$l" || {
                      echo "the ${name} host launcher lost $wanted"
                      exit 1
                    }
                  done
                  grep -qF 'if [ "0" = 1 ]; then' "$l" || {
                    echo "the ${name} host launcher was not built with guest = false"
                    exit 1
                  }
                '') hosts
              )
              + ''
                touch "$out"
              ''
            );

          checks.launcher-restart-loop = pkgs.runCommand "steam-launcher-restart-loop" { } ''
            source ${self'.packages.steam-arm64}/bin/steam-arm64
            expect() {
              local want_status=$1 want_runs=$2 label=$3
              shift 3
              runs=0
              local status=0
              restart_loop "$@" 2>"$TMPDIR/said" || status=$?
              if [ "$status" -ne "$want_status" ] || [ "$runs" -ne "$want_runs" ]; then
                echo "$label: exit $status after $runs runs, wanted exit $want_status after $want_runs"
                cat "$TMPDIR/said"
                exit 1
              fi
            }
            asks_again() {
              runs=$((runs + 1))
              return 42
            }
            expect 42 5 "five quick restart requests in a row stop the loop" asks_again
            grep -qF 'that is a loop, not an update' "$TMPDIR/said" || {
              echo "giving up on a restart loop says nothing to the user:"
              cat "$TMPDIR/said"
              exit 1
            }
            finishes() {
              runs=$((runs + 1))
              return 0
            }
            expect 0 1 "a clean exit returns at once" finishes
            fails() {
              runs=$((runs + 1))
              return 3
            }
            expect 3 1 "a failure returns its own status at once" fails
            updates_then_runs() {
              runs=$((runs + 1))
              if [ "$runs" -eq 5 ]; then
                SECONDS=$((SECONDS + 60))
              fi
              if [ "$runs" -lt 9 ]; then
                return 42
              fi
              return 0
            }
            expect 0 9 "a run that stayed up a minute resets the count, so four short, one long and three short restarts run on" updates_then_runs
            if ! grep -qF 'restart_loop "$run" "$@"' ${self'.packages.steam-arm64}/bin/steam-arm64; then
              echo "the launcher's main no longer hands the client to restart_loop"
              exit 1
            fi
            touch "$out"
          '';

          checks.steam-arm64-compat-tools =
            let
              tool =
                pkgs.runCommand "fake-compat-tool"
                  {
                    outputs = [
                      "out"
                      "steamcompattool"
                    ];
                  }
                  ''
                    mkdir -p "$out" "$steamcompattool"
                    touch "$steamcompattool/compatibilitytool.vdf"
                  '';
              withTool = launcher: launcher.override { extraCompatTools = [ tool ]; };
            in
            pkgs.runCommand "steam-arm64-compat-tools" { } ''
              for l in ${withTool self'.packages.steam-arm64}/bin/steam-arm64 \
                ${withTool self'.packages.steam-x86}/bin/steam-x86; do
                grep -qF 'STEAM_EXTRA_COMPAT_TOOLS_PATHS="${tool.steamcompattool}' "$l" || {
                  echo "$l does not hand the client the steamcompattool output of a tool it was built with"
                  exit 1
                }
                grep -qF -- '-e "$var=' "$l" || {
                  echo "$l no longer forwards its environment into the guest, so the tools stay on the host"
                  exit 1
                }
              done
              for l in ${self'.packages.steam-arm64}/bin/steam-arm64 ${self'.packages.steam-x86}/bin/steam-x86; do
                grep -qF 'if [ -n "" ]; then' "$l" || {
                  echo "$l names compatibility tools nobody asked for"
                  exit 1
                }
              done
              touch "$out"
            '';

          checks.launcher-host-refuses-other-pages =
            pkgs.runCommand "steam-launcher-host-refuses-other-pages" { }
              ''
                for l in ${self'.packages.steam-arm64-host}/bin/steam-arm64 ${self'.packages.steam-x86-host}/bin/steam-x86; do
                  if ! (
                    source "$l"
                    require_4k_pages 4096
                  ); then
                    echo "$l refuses a 4096-byte page kernel, the one it is for"
                    exit 1
                  fi
                  for pages in 16384 65536; do
                    if (
                      source "$l"
                      require_4k_pages "$pages" 2>"$TMPDIR/refusal"
                    ); then
                      echo "$l accepts a $pages-byte page kernel, where Valve's client and FEX cannot run"
                      exit 1
                    fi
                    grep -qF -- "$pages-byte pages" "$TMPDIR/refusal" || {
                      echo "$l refuses $pages-byte pages without naming them:"
                      cat "$TMPDIR/refusal"
                      exit 1
                    }
                    grep -qF "muvm's 4K-page guest" "$TMPDIR/refusal" || {
                      echo "$l refuses without naming the guest launcher to run instead:"
                      cat "$TMPDIR/refusal"
                      exit 1
                    }
                  done
                done
                touch "$out"
              '';

          checks.client-tree = pkgs.runCommand "steam-arm64-client-tree" { } ''
            test -d ${self'.packages.default}/steamrtarm64/libs
            touch "$out"
          '';

          checks.update-reports-the-channel-that-moved = pkgs.runCommand "steam-arm64-update-report" { } ''
            export GITHUB_OUTPUT="$TMPDIR/out"
            source ${./scripts/update.sh}
            pin_client() {
              local entry
              entry="''${!1}"
              cur="''${entry%|*}"
              case "''${entry##*|}" in
              same) seen+=("$cur") ;;
              moved)
                seen+=("$cur")
                changed+=("$cur")
                updated=true
                ;;
              fail) return 2 ;;
              esac
            }
            run() {
              : >"$GITHUB_OUTPUT"
              set +e
              (pin_channels "stable publicbeta")
              status=$?
              set -e
            }
            want() {
              if [ "$(grep "^$1=" "$GITHUB_OUTPUT" | tail -1 | cut -d= -f2-)" != "$2" ]; then
                echo "$3: expected $1=$2"
                cat "$GITHUB_OUTPUT"
                exit 1
              fi
            }

            stable="steam-arm64-client|100|100|same" publicbeta="steam-arm64-client-beta|200|201|moved" run
            want package_name steam-arm64-client-beta "only the beta moved"
            want old_version 200 "only the beta moved"
            want new_version 201 "only the beta moved"
            want updated true "only the beta moved"

            stable="steam-arm64-client|100|101|moved" publicbeta="steam-arm64-client-beta|200|201|moved" run
            want package_name steam-arm64-client "both moved"
            want old_version "100 (beta 200)" "both moved"
            want new_version "101 (beta 201)" "both moved"

            stable="steam-arm64-client|100|100|same" publicbeta="steam-arm64-client-beta|200|200|same" run
            want updated false "nothing moved"
            want new_version 100 "nothing moved"

            stable="steam-arm64-client|100|100|same" publicbeta="steam-arm64-client-beta|200|201|fail" run
            if [ "$status" -ne 2 ]; then
              echo "a failing channel must exit with its own status, 2, not $status"
              exit 1
            fi
            want package_name steam-arm64-client-beta "the beta failed"
            want updated false "the beta failed"
            touch "$out"
          '';
        };

      flake.overlays.default = final: prev: {
        muvm = final.callPackage ./muvm-patched.nix { inherit (prev) muvm; };
        steam-arm64-client = final.callPackage ./package.nix { channel = "stable"; };
        steam-arm64-client-beta = final.callPackage ./package.nix { channel = "publicbeta"; };
        steam-runtime-arm64 = final.callPackage ./runtime.nix { };
        steam-runtime-arm64-libs = final.callPackage ./runtime-libs.nix { };
        steam-arm64-fhs = final.callPackage ./fhs.nix { };
        steam-x86-rootfs = final.callPackage ./fex-rootfs-x86.nix { };
        fex-interpreter = final.callPackage ./fex-interpreter.nix { };
        steam-arm64 = final.callPackage ./launcher.nix { channel = "stable"; };
        steam-arm64-beta = final.callPackage ./launcher.nix {
          channel = "publicbeta";
          steam-arm64-client = final.steam-arm64-client-beta;
        };
      };
    };
}
