{
  linkFarm,
  writeShellScript,
  shutdown,
}:
let
  update = writeShellScript "steamos-update" ''
    case " $* " in
    *" --supports-duplicate-detection "*) exit 0 ;;
    esac
    exit 7
  '';
  selectBranch = writeShellScript "steamos-select-branch" ''
    case "''${1:-}" in
    -l | -c) echo rel ;;
    *)
      echo "steamos-select-branch: this is not SteamOS; the client's own channel is package/beta in its Steam root" >&2
      exit 1
      ;;
    esac
  '';
  sessionSelect = writeShellScript "steamos-session-select" ''
    set -o errexit
    set -o nounset
    ${shutdown}
  '';
in
linkFarm "steamos-stubs" {
  "bin/steamos-polkit-helpers/steamos-update" = update;
  "bin/steamos-select-branch" = selectBranch;
  "bin/steamos-polkit-helpers/steamos-select-branch" = selectBranch;
  "bin/steamos-session-select" = sessionSelect;
}
