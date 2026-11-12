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
          fakePageSwitch = pkgs.writeShellScriptBin "page-switch" ''
            [ "$1" = 4k ] || exit 2
            shift
            if [ "''${FAKE_SWITCH:-}" = gives ]; then
              FAKE_PAGESIZE=4096 exec "$@"
            fi
            echo "Cannot select 4k userspace pages: Invalid argument" >&2
            exit 1
          '';
          evalModule =
            {
              hostSystem ? system,
              overlay ? true,
              kernelPages ? null,
              settings ? { },
              extra ? { },
            }:
            inputs.nixpkgs.lib.nixosSystem {
              system = hostSystem;
              modules = [
                inputs.self.nixosModules.default
                extra
                {
                  nixpkgs.config = consumerConfig;
                  nixpkgs.overlays = lib.optional overlay inputs.self.overlays.default;
                  boot.isContainer = true;
                  boot.kernelPatches = lib.optional (kernelPages != null) {
                    name = "${kernelPages}-pages";
                    patch = null;
                    structuredExtraConfig."ARM64_${kernelPages}_PAGES" = lib.kernel.yes;
                  };
                  networking.useHostResolvConf = lib.mkForce false;
                  system.stateVersion = lib.trivial.release;
                  programs.steam-arm64 = {
                    enable = true;
                  }
                  // settings;
                }
              ];
            };
        in
        {
          std.detect.shell = {
            mode = "gate";
            paths = [ "." ];
          };

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
          packages.host-probe =
            let
              probed =
                (evalModule {
                  kernelPages = "4K";
                  settings = {
                    hostBinfmt = true;
                    x86.enable = true;
                  };
                }).config;
            in
            pkgs.callPackage ./host-probe.nix {
              registrations = probed.environment.etc."binfmt.d/nixos.conf".source;
              interpreters = lib.mapAttrs (_: r: r.interpreter) probed.boot.binfmt.registrations;
              rootfs = probed.fileSystems."/run/fex-emu/rootfs".device;
              mountOptions = lib.remove "nofail" probed.fileSystems."/run/fex-emu/rootfs".options;
              steam-arm64-host = probed.programs.steam-arm64.package;
              steam-x86-host = probed.programs.steam-arm64.x86.package;
            };

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
            src=${pkgs.muvm.src}/crates/muvm/src
            if [ ! -d "$src" ]; then
              echo "muvm ${pkgs.muvm.version} has no $src; find where its source lives now."
              exit 1
            fi
            if grep -rqE 'DBUS_SOCKET|join\("bus"\)|DBUS_SESSION_BUS_ADDRESS' "$src"; then
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
            src=${pkgs.muvm.src}/crates/muvm/src
            if [ ! -d "$src" ]; then
              echo "muvm ${pkgs.muvm.version} has no $src; find where its source lives now."
              exit 1
            fi
            if grep -rq system_bus_socket "$src"; then
              echo "muvm ${pkgs.muvm.version} now names the system bus socket itself."
              echo "Read what it does. If the guest reaches the host's system bus, delete"
              echo "muvm-bridge-system-bus.patch, the DBUS_SYSTEM_BUS_ADDRESS lines in both"
              echo "guest-run scripts, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-shm-divergence = pkgs.runCommand "muvm-shm-divergence" { } ''
            x11=${pkgs.muvm.src}/crates/muvm/src/guest/bridge/x11.rs
            if [ ! -f "$x11" ]; then
              echo "muvm ${pkgs.muvm.version} has no $x11; find where its X11 bridge lives now."
              exit 1
            fi
            if grep -q MIT-SHM "$x11"; then
              echo "muvm ${pkgs.muvm.version} now names MIT-SHM in its own X11 bridge."
              echo "Read what it does there. If it masks or proxies the extension,"
              echo "delete muvm-mask-mit-shm.patch, its override in launcher.nix, and this check."
              exit 1
            fi
            touch "$out"
          '';

          checks.muvm-groups-divergence = pkgs.runCommand "muvm-groups-divergence" { } ''
            user=${pkgs.muvm.src}/crates/muvm/src/guest/user.rs
            if [ ! -f "$user" ]; then
              echo "muvm ${pkgs.muvm.version} has no $user; find where the guest's user setup lives now."
              exit 1
            fi
            if grep -q setgroups "$user"; then
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
                  echo "Every ELF file in Valve's aarch64 client now has LOAD segments aligned to 16K or more, so the client itself would load on a 16K-page kernel."
                  echo "This is a decision day, not a switch to flip: Proton (ARM64) carries FEX, which refuses a non-4K host, so on a 16K"
                  echo "kernel Windows games would still need muvm's guest while the client and native games could leave it. Decide whether"
                  echo "the native client runs on the host with Proton (ARM64) kept in the guest, or everything stays in the guest, then"
                  echo "change this check to match the decision."
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
              test -x ${overlaid.steam-x86}/bin/steam-x86
              test -x ${overlaid.steam-x86-fhs}/bin/steam-x86-fhs
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

          checks.remote-play-ports-published =
            let
              ours =
                settings:
                (evalModule {
                  kernelPages = "16K";
                  inherit settings;
                }).config.networking.firewall;
              nixpkgs' =
                settings:
                (inputs.nixpkgs.lib.nixosSystem {
                  system = "x86_64-linux";
                  modules = [
                    {
                      nixpkgs.config = consumerConfig;
                      boot.isContainer = true;
                      networking.useHostResolvConf = lib.mkForce false;
                      system.stateVersion = lib.trivial.release;
                      programs.steam = {
                        enable = true;
                      }
                      // settings;
                    }
                  ];
                }).config.networking.firewall;
              combos = {
                "both options" = {
                  remotePlay.openFirewall = true;
                  localNetworkGameTransfers.openFirewall = true;
                };
                "remotePlay alone" = {
                  remotePlay.openFirewall = true;
                };
                "localNetworkGameTransfers alone" = {
                  localNetworkGameTransfers.openFirewall = true;
                };
                "neither" = { };
              };
              sorted = lib.sort lib.lessThan;
              rangesOf = map (r: "${toString r.from}-${toString r.to}");
              differs =
                label: settings:
                let
                  mine = ours settings;
                  theirs = nixpkgs' settings;
                  show =
                    fw:
                    "TCP ${toString (sorted fw.allowedTCPPorts)}; UDP ${toString (sorted fw.allowedUDPPorts)}; UDP ranges ${toString (rangesOf fw.allowedUDPPortRanges)}";
                in
                lib.optional (show mine != show theirs)
                  "${label}: programs.steam-arm64 opens ${show mine} but nixpkgs' programs.steam opens ${show theirs}";
              problems = lib.concatLists (lib.mapAttrsToList differs combos);
              everything = nixpkgs' combos."both options";
              expand = r: lib.range r.from r.to;
              published =
                map (p: "${toString p}:${toString p}") everything.allowedTCPPorts
                ++ map (p: "${toString p}:${toString p}/udp") (
                  everything.allowedUDPPorts ++ lib.concatMap expand everything.allowedUDPPortRanges
                );
            in
            pkgs.runCommand "steam-remote-play-ports-published" { } (
              lib.concatMapStringsSep "\n" (p: "echo ${lib.escapeShellArg p}") problems
              + lib.optionalString (problems != [ ]) "\nexit 1\n"
              + ''
                for l in ${self'.packages.steam-arm64}/bin/steam-arm64 ${self'.packages.steam-x86}/bin/steam-x86; do
                  for p in ${lib.escapeShellArgs published}; do
                    if ! grep -qF -- "-p $p" "$l"; then
                      echo "$l no longer publishes $p: passt cannot carry the guest's own LAN"
                      echo "broadcast, so a Steam Link, Remote Play or game-transfer peer on the LAN"
                      echo "reaches the client only through the ports published out of the guest,"
                      echo "which are the ones programs.steam-arm64's firewall options open"
                      exit 1
                    fi
                  done
                done
                touch "$out"
              ''
            );

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
            grep -q 'FEX_APP_CONFIG_LOCATION=@appconfig@' ${./guest-run-x86.sh} \
              || {
                echo "guest-run does not name the per-application profile directory: FEX reads"
                echo "profiles only from FEX_APP_CONFIG_LOCATION, so without it the web helper's"
                echo "Multiblock profile in fex-emulator-x86 is shipped and never applied"
                exit 1
              }
            for g in ${./guest-run.sh} ${./guest-run-x86.sh}; do
              grep -q 'elif ! dbus-send --system' "$g" \
                || {
                  echo "$g warns about the system bus without asking it first: on the host the"
                  echo "bridged socket is absent by design and the system bus answers directly,"
                  echo "so an else branch there warns on every launch"
                  exit 1
                }
              if grep -q 'not reachable from the guest' "$g"; then
                echo "$g says 'from the guest', which is false on the host path"
                exit 1
              fi
            done
            touch "$out"
          '';

          checks.host-probe-pins-follow-the-standard =
            pkgs.runCommand "host-probe-pins-follow-the-standard" { }
              ''
                workflow=${./.github/workflows/host-probe.yml}
                ours=$(grep -oE 'uses: [^ ]+' "$workflow")
                if [ -z "$ours" ]; then
                  echo "host-probe.yml uses no action at all"
                  exit 1
                fi
                while IFS= read -r use; do
                  if ! grep -qxE 'uses: [^ @]+@[0-9a-f]{40}' <<<"$use"; then
                    echo "host-probe.yml has '$use', which is not pinned to a 40-character commit;"
                    echo "a tag or a branch moves under the workflow, so pin the commit the"
                    echo "standard's workflows pin."
                    exit 1
                  fi
                done <<<"$ours"
                theirs=$(grep -rhoE 'uses: [^ ]+@[0-9a-f]{40}' ${inputs.std}/.github/workflows/)
                while IFS= read -r pin; do
                  if ! grep -qxF -- "$pin" <<<"$theirs"; then
                    echo "host-probe.yml pins '$pin', which none of the standard's workflows carries."
                    echo "This workflow sits outside the synced callers, so dependabot moves the"
                    echo "standard's pins and this check moves ours: set it to the standard's pin."
                    exit 1
                  fi
                done <<<"$ours"
                triggers=$(sed -n '/^on:/,/^permissions:/{/^  [a-z_]*:/p}' "$workflow")
                if [ "$triggers" != "  workflow_dispatch:" ]; then
                  echo "host-probe.yml runs on something besides workflow_dispatch:"
                  echo "$triggers"
                  echo "the probe needs root on a runner and proves one host; it is run by hand."
                  exit 1
                fi
                grep -qF 'runs-on: ubuntu-24.04-arm' "$workflow" || {
                  echo "host-probe.yml no longer runs on ubuntu-24.04-arm, the 4K-page aarch64 runner"
                  exit 1
                }
                grep -qF 'nix run .#host-probe' "$workflow" || {
                  echo "host-probe.yml no longer runs packages.host-probe"
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

          checks.module-refusals =
            let
              ours = sys: map (a: a.message) (lib.filter (a: !a.assertion) sys.config.assertions);
              refusal =
                {
                  name,
                  expect,
                  ...
                }@scenario:
                let
                  failed = ours (
                    evalModule (
                      builtins.removeAttrs scenario [
                        "name"
                        "expect"
                      ]
                    )
                  );
                  matched = e: lib.filter (lib.hasInfix e) failed;
                in
                lib.concatMap (
                  e:
                  lib.optional (lib.length (matched e) != 1)
                    "${name}: wanted one refusal naming '${e}', got ${toString (lib.length (matched e))} among: ${lib.concatStringsSep " | " failed}"
                ) expect
                ++
                  lib.optional (lib.length failed != lib.length expect)
                    "${name}: ${toString (lib.length failed)} assertions failed, wanted ${toString (lib.length expect)}: ${lib.concatStringsSep " | " failed}";
              refusals = lib.concatMap refusal [
                {
                  name = "an x86-64 host";
                  hostSystem = "x86_64-linux";
                  settings.pageSize = 4096;
                  expect = [ "aarch64 only" ];
                }
                {
                  name = "no overlay";
                  overlay = false;
                  settings.pageSize = 4096;
                  expect = [ "overlays.default" ];
                }
                {
                  name = "a kernel that states no granule and no stated pageSize";
                  expect = [ "states no ARM64_*_PAGES" ];
                }
                {
                  name = "pageSize 4096 on a 16K kernel";
                  kernelPages = "16K";
                  settings.pageSize = 4096;
                  expect = [ "contradicts the kernel's configuration" ];
                }
                {
                  name = "hostBinfmt on a 16K kernel";
                  kernelPages = "16K";
                  settings.hostBinfmt = true;
                  expect = [ "with no pageSwitch to give a program 4K pages" ];
                }
                {
                  name = "pageSwitch on a 4K kernel";
                  kernelPages = "4K";
                  settings.pageSwitch = fakePageSwitch;
                  expect = [ "the switch would never be asked" ];
                }
                {
                  name = "the x86 client with pageSwitch without hostBinfmt";
                  kernelPages = "16K";
                  settings = {
                    pageSwitch = fakePageSwitch;
                    x86.enable = true;
                  };
                  expect = [ "needs programs.steam-arm64.hostBinfmt" ];
                }
                {
                  name = "hostBinfmt beside another x86-64 handler";
                  kernelPages = "4K";
                  settings.hostBinfmt = true;
                  extra.boot.binfmt.registrations.qemu = {
                    magicOrExtension = ''\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00'';
                    interpreter = "/bin/true";
                  };
                  expect = [ "2 handlers for FEX-x86_64's ELF magic (FEX-x86_64, qemu)" ];
                }
                {
                  name = "the x86 client on a 4K host without hostBinfmt";
                  kernelPages = "4K";
                  settings.x86.enable = true;
                  expect = [ "needs programs.steam-arm64.hostBinfmt" ];
                }
              ];
              hostSys = evalModule {
                kernelPages = "4K";
                settings = {
                  hostBinfmt = true;
                  x86.enable = true;
                };
              };
              guestSys = evalModule {
                kernelPages = "16K";
                settings.x86.enable = true;
              };
              switchSys = evalModule {
                kernelPages = "16K";
                settings = {
                  pageSwitch = fakePageSwitch;
                  hostBinfmt = true;
                  x86.enable = true;
                };
              };
              hostCfg = hostSys.config;
              guestCfg = guestSys.config;
              switchCfg = switchSys.config;
              want = label: cond: lib.optional (!cond) label;
              wiring =
                want
                  "a 4K host with hostBinfmt and x86 passes every assertion: ${lib.concatStringsSep " | " (ours hostSys)}"
                  (ours hostSys == [ ])
                ++
                  want "a 16K kernel with x86 passes every assertion: ${lib.concatStringsSep " | " (ours guestSys)}"
                    (ours guestSys == [ ])
                ++ want "the 16K kernel's granule is derived" (guestCfg.programs.steam-arm64.pageSize == 16384)
                ++ want "the 4K kernel's granule is derived" (hostCfg.programs.steam-arm64.pageSize == 4096)
                ++ want "the host runs the native client's host launcher" (
                  hostCfg.programs.steam-arm64.package.name == "steam-arm64-host"
                )
                ++ want "the host runs the x86 client's host launcher" (
                  hostCfg.programs.steam-arm64.x86.package.name == "steam-x86-host"
                )
                ++ want "the 16K kernel runs the native client's guest launcher" (
                  guestCfg.programs.steam-arm64.package.name == "steam-arm64"
                )
                ++ want "the 16K kernel runs the x86 client's guest launcher" (
                  guestCfg.programs.steam-arm64.x86.package.name == "steam-x86"
                )
                ++ want "both launchers are installed" (
                  lib.all (p: lib.elem p hostCfg.environment.systemPackages) [
                    hostCfg.programs.steam-arm64.package
                    hostCfg.programs.steam-arm64.x86.package
                  ]
                )
                ++ want "the handler is FEX's own binary, not a shell wrapper" (
                  lib.all (r: lib.hasSuffix "/bin/FEX" r.interpreter && !r.wrapInterpreterInShell) (
                    lib.attrValues hostCfg.boot.binfmt.registrations
                  )
                )
                ++ want "the FEX rootfs is mounted read-only, nosuid and nodev from the pinned EROFS image" (
                  hostCfg.fileSystems."/run/fex-emu/rootfs".fsType == "erofs"
                  && lib.hasInfix "steam-x86-fedora-rootfs" hostCfg.fileSystems."/run/fex-emu/rootfs".device
                  && lib.all (o: lib.elem o hostCfg.fileSystems."/run/fex-emu/rootfs".options) [
                    "ro"
                    "nosuid"
                    "nodev"
                  ]
                )
                ++ want "FEX_ROOTFS is set session-wide" (
                  hostCfg.environment.sessionVariables.FEX_ROOTFS == "/run/fex-emu/rootfs"
                )
                ++ want "a 16K kernel registers no host handler" (guestCfg.boot.binfmt.registrations == { })
                ++ want "a 16K kernel mounts no rootfs" (!(guestCfg.fileSystems ? "/run/fex-emu/rootfs"))
                ++ want "a 16K kernel sets no FEX_ROOTFS" (!(guestCfg.environment.sessionVariables ? FEX_ROOTFS))
                ++
                  want
                    "a 16K kernel with pageSwitch, hostBinfmt and x86 passes every assertion: ${lib.concatStringsSep " | " (ours switchSys)}"
                    (ours switchSys == [ ])
                ++
                  want
                    "with pageSwitch both clients keep the guest launcher, muvm being the path when the switch refuses"
                    (
                      switchCfg.programs.steam-arm64.package.name == "steam-arm64"
                      && switchCfg.programs.steam-arm64.x86.package.name == "steam-x86"
                    )
                ++ want "with pageSwitch hostBinfmt registers FEX and mounts its rootfs" (
                  switchCfg.boot.binfmt.registrations ? FEX-x86_64 && switchCfg.fileSystems ? "/run/fex-emu/rootfs"
                );
              problems = refusals ++ wiring;
            in
            pkgs.runCommand "steam-arm64-module-refusals" { } (
              if problems == [ ] then
                ''
                  conf=${hostCfg.environment.etc."binfmt.d/nixos.conf".source}
                  registered() {
                    if ! grep -qF -- "$2" "$conf" || ! grep -qF -- "$3" "$conf"; then
                      echo "$1 is not registered on its ELF magic with the F flag; rendered:"
                      cat "$conf"
                      exit 1
                    fi
                  }
                  registered FEX-x86_64 ':FEX-x86_64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:' ':/run/binfmt/FEX-x86_64:PCF'
                  registered FEX-i386 ':FEX-i386:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00:' ':/run/binfmt/FEX-i386:PCF'
                  echo "every refusal fires for its own reason and the host and guest wiring hold" > "$out"
                ''
              else
                lib.concatMapStringsSep "\n" (p: "echo ${lib.escapeShellArg p}") problems + "\nexit 1\n"
            );

          checks.steamos-stubs =
            let
              client = self'.packages.default;
              native = self'.packages.steam-arm64-fhs.fhsenv;
              x86 = self'.packages.steam-x86-fhs.fhsenv;
            in
            pkgs.runCommand "steam-arm64-steamos-stubs" { } ''
              refuse() {
                echo "$1"
                exit 1
              }
              for rootfs in ${native} ${x86}; do
                for h in steamos-polkit-helpers/steamos-update steamos-select-branch \
                  steamos-polkit-helpers/steamos-select-branch steamos-session-select; do
                  test -x "$rootfs/usr/bin/$h" || refuse "$rootfs has no /usr/bin/$h, which Valve's client calls in Deck mode"
                done
                for absent in steamos-update steamos-wifi-set-backend steamos-polkit-helpers/steamos-priv-write \
                  steamos-polkit-helpers/steamos-set-timezone steamos-polkit-helpers/steamos-set-hostname; do
                  if [ -e "$rootfs/usr/bin/$absent" ]; then
                    refuse "$rootfs ships /usr/bin/$absent: nothing calls the bare steamos-update, and the others would report success for a change that did not happen or write a fact the system declares"
                  fi
                done
                update="$rootfs/usr/bin/steamos-polkit-helpers/steamos-update"
                "$update" --supports-duplicate-detection || refuse "the duplicate-detection probe must exit 0"
                status=0
                "$update" check || status=$?
                [ "$status" -eq 7 ] || refuse "an update check must exit 7, SteamOS's no update available, got $status"
                branch="$rootfs/usr/bin/steamos-select-branch"
                [ "$("$branch" -l)" = rel ] || refuse "steamos-select-branch -l must list rel alone"
                [ "$("$branch" -c)" = rel ] || refuse "steamos-select-branch -c must report rel"
                if "$branch" beta 2>/dev/null; then
                  refuse "steamos-select-branch accepted a switch; the client's channel is package/beta, not an OS branch"
                fi
              done
              select=${native}/usr/bin/steamos-session-select
              if "$select" plasma 2>/dev/null; then
                refuse "the native steamos-session-select ran without STEAM_ARM64_ROOT"
              fi
              mkdir -p "$TMPDIR/empty" "$TMPDIR/root/steamrtarm64"
              if STEAM_ARM64_ROOT="$TMPDIR/empty" "$select" plasma 2>/dev/null; then
                refuse "the native steamos-session-select ran with no client in the Steam root"
              fi
              printf '#!%s\nprintf "%%s\\n" "$@" >"%s"\n' "${pkgs.bash}/bin/sh" "$TMPDIR/args" >"$TMPDIR/root/steamrtarm64/steam"
              chmod +x "$TMPDIR/root/steamrtarm64/steam"
              STEAM_ARM64_ROOT="$TMPDIR/root" "$select" plasma
              [ "$(cat "$TMPDIR/args")" = -shutdown ] || refuse "the native steamos-session-select did not ask the client to shut down: $(cat "$TMPDIR/args")"
              grep -qF -- '${pkgs.steam-unwrapped}/bin/steam -shutdown' ${x86}/usr/bin/steamos-session-select \
                || refuse "the x86 steamos-session-select does not shut Valve's x86 client down through its steam.sh"
              grep -qF '${self'.packages.fex-interpreter}/bin/FEXInterpreter' ${x86}/usr/bin/steamos-session-select \
                || refuse "the x86 steamos-session-select does not run steam.sh under FEX, so uname would not say x86_64"
              for pair in 'steam steamos-polkit-helpers/steamos-update' 'steamclient.so steamos-select-branch' 'steamui.so steamos-session-select'; do
                set -- $pair
                grep -qaF "$2" ${client}/steamrtarm64/$1 \
                  || refuse "Valve's client ${client.version} no longer names $2 in steamrtarm64/$1: delete that stub from steamos-stubs.nix and this line"
              done
              touch "$out"
            '';

          checks.launcher-chooses-a-path =
            let
              fakeGetconf = pkgs.writeShellScriptBin "getconf" ''
                echo "$FAKE_PAGESIZE"
              '';
              variant =
                launcher: args:
                "${launcher.override ({ glibc = fakeGetconf; } // args)}/bin/${launcher.meta.mainProgram}";
              launchers =
                lib.concatMap
                  (l: [
                    "guest switch ${variant l { pageSwitch = fakePageSwitch; }}"
                    "guest none ${variant l { }}"
                    "host switch ${
                      variant l {
                        guest = false;
                        pageSwitch = fakePageSwitch;
                      }
                    }"
                    "host none ${variant l { guest = false; }}"
                  ])
                  [
                    self'.packages.steam-arm64
                    self'.packages.steam-x86
                  ];
            in
            pkgs.runCommand "steam-launcher-chooses-a-path" { } ''
              expect() {
                local l=$1 pages=$2 switch=$3 want=$4 got status=0
                got=$(FAKE_PAGESIZE=$pages FAKE_SWITCH=$switch bash -c 'source "$1"; choose_path; echo "$path"' _ "$l" 2>"$TMPDIR/said") || status=$?
                if [ "$want" = refused ]; then
                  if [ "$status" = 0 ]; then
                    echo "$l on $pages-byte pages, switch $switch: chose $got, wanted a refusal"
                    cat "$TMPDIR/said"
                    exit 1
                  fi
                elif [ "$status" != 0 ] || [ "$got" != "$want" ]; then
                  echo "$l on $pages-byte pages, switch $switch: chose ''${got:-nothing} with exit $status, wanted $want"
                  cat "$TMPDIR/said"
                  exit 1
                fi
                if [ ! -s "$TMPDIR/said" ]; then
                  echo "$l on $pages-byte pages, switch $switch: chose without saying which path or why"
                  exit 1
                fi
              }
              said() {
                grep -qF -- "$2" "$TMPDIR/said" || {
                  echo "$1 does not name $2:"
                  cat "$TMPDIR/said"
                  exit 1
                }
              }
              for entry in ${lib.escapeShellArgs launchers}; do
                read -r kind switch l <<<"$entry"
                expect "$l" 4096 gives host
                for pages in 16384 65536; do
                  case "$kind $switch" in
                  "guest switch")
                    expect "$l" "$pages" gives switch
                    expect "$l" "$pages" refuses guest
                    said "$l" "Invalid argument"
                    ;;
                  "guest none")
                    expect "$l" "$pages" refuses guest
                    ;;
                  "host switch")
                    expect "$l" "$pages" gives switch
                    expect "$l" "$pages" refuses refused
                    said "$l" "Invalid argument"
                    ;;
                  "host none")
                    expect "$l" "$pages" refuses refused
                    for named in "$pages-byte pages" "-host package" "muvm's 4K-page guest" "programs.steam-arm64"; do
                      said "$l" "$named"
                    done
                    ;;
                  esac
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

      flake.nixosModules.default = import ./module.nix;

      flake.overlays.default = final: prev: {
        muvm = final.callPackage ./muvm-patched.nix { inherit (prev) muvm; };
        steam-arm64-client = final.callPackage ./package.nix { channel = "stable"; };
        steam-arm64-client-beta = final.callPackage ./package.nix { channel = "publicbeta"; };
        steam-runtime-arm64 = final.callPackage ./runtime.nix { };
        steam-runtime-arm64-libs = final.callPackage ./runtime-libs.nix { };
        steam-arm64-fhs = final.callPackage ./fhs.nix { };
        steam-x86-rootfs = final.callPackage ./fex-rootfs-x86.nix { };
        fex-interpreter = final.callPackage ./fex-interpreter.nix { };
        fex-emulator-x86 = final.callPackage ./fex-emulator-x86.nix { };
        steam-x86-fhs = final.callPackage ./fhs-x86.nix { steam-x86-entry = final.steam-unwrapped; };
        steam-x86 = final.callPackage ./launcher-x86.nix { };
        steam-arm64 = final.callPackage ./launcher.nix { channel = "stable"; };
        steam-arm64-beta = final.callPackage ./launcher.nix {
          channel = "publicbeta";
          steam-arm64-client = final.steam-arm64-client-beta;
        };
      };
    };
}
