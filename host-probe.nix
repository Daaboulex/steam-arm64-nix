{
  lib,
  writeShellApplication,
  coreutils,
  util-linux,
  glibc,
  gnugrep,
  registrations,
  interpreters,
  rootfs,
  mountOptions,
  steam-arm64-host,
  steam-x86-host,
}:
writeShellApplication {
  name = "host-probe";
  runtimeInputs = [
    coreutils
    util-linux
    glibc.bin
    gnugrep
  ];
  meta = {
    description = "Registers the module's FEX handlers and mounts its rootfs as root on a 4K-page aarch64 host, then runs both clients' doctors headless";
    platforms = [ "aarch64-linux" ];
  };
  text = ''
    pagesize=$(getconf PAGESIZE)
    if [ "$pagesize" != 4096 ]; then
      echo "host-probe: this kernel uses $pagesize-byte pages; the host path and FEX need 4096" >&2
      exit 1
    fi

    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
    unshare --user --map-root-user true

    sudo mkdir -p /run/binfmt /run/fex-emu/rootfs
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: interpreter: "sudo ln -sfn ${interpreter} /run/binfmt/${name}"
      ) interpreters
    )}
    if ! mountpoint -q /proc/sys/fs/binfmt_misc; then
      sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
    fi
    mapfile -t lines <${registrations}
    for line in "''${lines[@]}"; do
      [ -n "$line" ] || continue
      name=$(cut -d: -f2 <<<"$line")
      if [ -e "/proc/sys/fs/binfmt_misc/$name" ]; then
        echo "host-probe: $name was registered before this run"
      else
        printf '%s' "$line" | sudo tee /proc/sys/fs/binfmt_misc/register >/dev/null
        echo "host-probe: registered $name"
      fi
    done
    for name in ${lib.escapeShellArgs (lib.attrNames interpreters)}; do
      if [ ! -e "/proc/sys/fs/binfmt_misc/$name" ]; then
        echo "host-probe: $name is not registered after reading ${registrations}" >&2
        exit 1
      fi
    done

    if ! mountpoint -q /run/fex-emu/rootfs; then
      sudo mount -t erofs -o ${lib.concatStringsSep "," mountOptions} ${rootfs} /run/fex-emu/rootfs
    fi
    export FEX_ROOTFS=/run/fex-emu/rootfs
    said=$(/run/fex-emu/rootfs/usr/bin/echo hi)
    if [ "$said" != hi ]; then
      echo "host-probe: an x86-64 binary from the rootfs did not run through FEX-x86_64: '$said'" >&2
      exit 1
    fi
    echo "host-probe: x86-64 runs through FEX-x86_64 on this $pagesize-byte page host"

    status=0
    require() {
      local report=$1
      shift
      for line in "$@"; do
        if ! grep -qxF "ok    $line" <<<"$report"; then
          echo "host-probe: the doctor did not report ok for: $line" >&2
          status=1
        fi
      done
    }

    doctor_status=0
    native=$(${steam-arm64-host}/bin/steam-arm64 --doctor 2>&1) || doctor_status=$?
    printf '%s\n' "$native"
    echo "host-probe: the native doctor exited $doctor_status; a runner has no GPU, no bus and no Steam apps, so the lines below decide"
    require "$native" \
      "the client runs on 4K pages" \
      "x86-64 binfmt handler registered" \
      "FEX rootfs mounted" \
      "an x86-64 binary runs through the rootfs" \
      "python3 for Valve's FEX tool" \
      "SteamOS helpers for Deck mode in place"

    doctor_status=0
    x86=$(${steam-x86-host}/bin/steam-x86 --doctor 2>&1) || doctor_status=$?
    printf '%s\n' "$x86"
    echo "host-probe: the x86 doctor exited $doctor_status; the lines below decide"
    require "$x86" \
      "the client runs on 4K pages" \
      "x86-64 binfmt handler registered" \
      "FEX rootfs mounted" \
      "an x86-64 binary runs through the rootfs" \
      "Valve's x86 bootstrap present" \
      "pressure-vessel's emulator manifest present" \
      "FEX's web helper profile present" \
      "SteamOS helpers for Deck mode in place"
    exit "$status"
  '';
}
