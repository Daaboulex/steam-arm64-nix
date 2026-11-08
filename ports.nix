let
  remotePlay = {
    tcp = [
      27036
      27037
    ];
    udp = [
      27031
      27036
    ];
  };
  localNetworkGameTransfers = {
    tcp = [ 27040 ];
    udp = [ ];
  };
  publish = suffix: map (p: "${toString p}:${toString p}${suffix}");
in
{
  inherit remotePlay localNetworkGameTransfers;
  published =
    publish "/udp" (remotePlay.udp ++ localNetworkGameTransfers.udp)
    ++ publish "" (remotePlay.tcp ++ localNetworkGameTransfers.tcp);
}
