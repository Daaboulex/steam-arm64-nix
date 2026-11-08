{ muvm, fex-interpreter }:
muvm.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    ./muvm-mask-mit-shm.patch
    ./muvm-bridge-dbus.patch
    ./muvm-vm-tuning.patch
    ./muvm-guest-groups.patch
    ./muvm-guest-dns.patch
    ./muvm-bridge-system-bus.patch
  ];
  postFixup = old.postFixup + ''
    wrapProgram "$out/bin/muvm" --prefix PATH : ${fex-interpreter}/bin
  '';
})
