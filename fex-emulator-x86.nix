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
  webhelperConfig = builtins.toJSON {
    Comment = "GLX direct via xcb; Multiblock off to dodge the intermittent web-helper crash (FEX 5336)";
    ThunksDB = {
      GL = 0;
    };
    Config = {
      Multiblock = "0";
    };
  };
in
runCommand "fex-emulator-x86"
  {
    nativeBuildInputs = [
      patchelf
      glibc.bin
    ];
    inherit manifest webhelperConfig;
  }
  ''
    mkdir -p "$out/bin" "$out/lib"
    cp -L ${fex}/bin/FEX "$out/bin/FEX"
    for b in FEXGetConfig FEXServer FEXBash FEXpidof FEXConfig FEXRootFSFetcher; do
      cp -L ${fex}/bin/$b "$out/bin/$b"
    done
    ln -s FEX "$out/bin/FEXInterpreter"
    cp -aL ${fex}/share "$out/share"

    loader=$(patchelf --print-interpreter ${fex}/bin/FEX)
    lname=$(basename "$loader")
    cp -L "$loader" "$out/lib/$lname"

    collect() {
      for f in "$@"; do
        [ -L "$f" ] && continue
        ldd "$f" | { grep -oE '/nix/store/[^ ()]+\.so[^ ()]*' || [ $? -eq 1 ]; }
      done
    }
    bundle() {
      while read -r lib; do
        [ -e "$out/lib/$(basename "$lib")" ] || cp -L "$lib" "$out/lib/"
      done
    }
    collect "$out"/bin/* | sort -u | bundle
    collect "$out"/lib/*.so* | sort -u | bundle
    collect "$out"/lib/*.so* | sort -u | bundle

    chmod -R u+w "$out"
    for f in "$out"/bin/FEX "$out"/bin/FEXGetConfig "$out"/bin/FEXServer "$out"/bin/FEXBash "$out"/bin/FEXpidof "$out"/bin/FEXConfig "$out"/bin/FEXRootFSFetcher; do
      patchelf --set-interpreter "$out/lib/$lname" --set-rpath "$out/lib" "$f"
    done
    for l in "$out"/lib/*.so*; do
      case "$l" in *"/$lname") continue ;; esac
      patchelf --set-rpath "$out/lib" "$l"
    done

    mkdir -p "$out/share/fex-emu/AppConfig"
    printf '%s' "$webhelperConfig" > "$out/share/fex-emu/AppConfig/steamwebhelper.json"
    printf '%s' "$manifest" > "$out/emulator.json"
  ''
