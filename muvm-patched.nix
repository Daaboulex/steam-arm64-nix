{ muvm }:
muvm.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./muvm-mask-mit-shm.patch ];
})
