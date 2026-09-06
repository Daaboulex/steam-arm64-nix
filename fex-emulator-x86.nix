{
  runCommand,
  patchelf,
  glibc,
  fex,
}:
let
  manifest = builtins.toJSON {
    emulator_v0 = {
      argv = "./bin/FEXInterpreter";
      server_argv = "./bin/FEXServer";
      environment = {
        FEX_PORTABLE = "1";
      };
      container_environment = {
        FEX_ROOTFS = "";
      };
      emulated_architectures = [
        "x86_64-linux-gnu"
        "i386-linux-gnu"
      ];
      required_architectures = [ "aarch64-linux-gnu" ];
      required_libraries = [
        "libc.so.6"
        "libstdc++.so.6"
        "libgcc_s.so.1"
      ];
    };
  };
in
runCommand "fex-emulator-x86"
  {
    nativeBuildInputs = [
      patchelf
      glibc.bin
    ];
    inherit manifest;
  }
  ''
    mkdir -p "$out/bin" "$out/lib"
    cp -L ${fex}/bin/FEX "$out/bin/FEX"
    for b in FEXGetConfig FEXServer FEXBash FEXpidof FEXConfig FEXRootFSFetcher; do
      cp -L ${fex}/bin/$b "$out/bin/$b" 2>/dev/null || true
    done
    ln -s FEX "$out/bin/FEXInterpreter"
    cp -aL ${fex}/share "$out/share" 2>/dev/null || true

    loader=$(patchelf --print-interpreter ${fex}/bin/FEX)
    lname=$(basename "$loader")
    cp -L "$loader" "$out/lib/$lname"

    collect() {
      for f in "$@"; do
        [ -L "$f" ] && continue
        ldd "$f" 2>/dev/null | { grep -oE '/nix/store/[^ ()]+\.so[^ ()]*' || true; }
      done
    }
    collect "$out"/bin/* | sort -u | while read -r lib; do
      cp -Ln "$lib" "$out/lib/" 2>/dev/null || true
    done
    collect "$out"/lib/*.so* | sort -u | while read -r lib; do
      cp -Ln "$lib" "$out/lib/" 2>/dev/null || true
    done
    collect "$out"/lib/*.so* | sort -u | while read -r lib; do
      cp -Ln "$lib" "$out/lib/" 2>/dev/null || true
    done

    chmod -R u+w "$out"
    for f in "$out"/bin/FEX "$out"/bin/FEXGetConfig "$out"/bin/FEXServer "$out"/bin/FEXBash "$out"/bin/FEXpidof "$out"/bin/FEXConfig "$out"/bin/FEXRootFSFetcher; do
      [ -f "$f" ] || continue
      patchelf --set-interpreter "$out/lib/$lname" --set-rpath "$out/lib" "$f" 2>/dev/null || true
    done
    for l in "$out"/lib/*.so*; do
      case "$l" in *"/$lname") continue ;; esac
      patchelf --set-rpath "$out/lib" "$l" 2>/dev/null || true
    done

    printf '%s' "$manifest" > "$out/emulator.json"
    true
  ''
