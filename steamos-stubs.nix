# Stand-ins for the SteamOS helper scripts the client runs in Deck mode
# (-steamos3). Valve's client calls them by path under /usr/bin, and there is no
# SteamOS here, so each answers "nothing to do" and the client carries on.
# Without steamos-update the client reports an update error; without the
# others it logs a failed call each time a Deck settings page is opened.
{ linkFarm, writeShellScript }:
let
  noop = name: writeShellScript name "exit 0";
in
linkFarm "steamos-stubs" {
  # Exit 7 is SteamOS's "no update available"; the flag is a capability probe.
  "bin/steamos-update" = writeShellScript "steamos-update" ''
    case "$*" in
      *--supports-duplicate-detection*) exit 0 ;;
    esac
    exit 7
  '';

  # The client's own channel is package/beta, not an OS branch. Report the one
  # branch there is and ignore a request to switch.
  "bin/steamos-select-branch" = writeShellScript "steamos-select-branch" ''
    case "''${1:-}" in
      -c | -l) echo stable ;;
    esac
  '';

  # The client may ask for its Wi-Fi backend to become iwd. The host keeps the
  # backend it has (NetworkManager), so accept and change nothing.
  "bin/steamos-wifi-set-backend" = noop "steamos-wifi-set-backend";

  # Deck mode writes brightness, TDP and fan values to sysfs and sets the
  # timezone through these. Neither is the client's to change on a NixOS host.
  "bin/steamos-polkit-helpers/steamos-priv-write" = noop "steamos-priv-write";
  "bin/steamos-polkit-helpers/steamos-set-timezone" = noop "steamos-set-timezone";
}
