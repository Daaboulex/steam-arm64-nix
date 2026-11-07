{ runCommand, fex }:
runCommand "fex-interpreter" { } ''
  mkdir -p "$out/bin"
  ln -s ${fex}/bin/FEX "$out/bin/FEXInterpreter"
  test -x "$out/bin/FEXInterpreter"
''
