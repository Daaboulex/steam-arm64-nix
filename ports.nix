let
  discovery = {
    tcp = [ ];
    udp = [ 27036 ];
    udpRanges = [ ];
  };
  remotePlay = {
    tcp = [
      27036
      27037
    ];
    udp = [
      10400
      10401
    ];
    udpRanges = [
      {
        from = 27031;
        to = 27035;
      }
    ];
  };
  localNetworkGameTransfers = {
    tcp = [ 27040 ];
    udp = [ ];
    udpRanges = [ ];
  };
  expand = range: builtins.genList (i: range.from + i) (range.to - range.from + 1);
  publish = suffix: map (p: "${toString p}:${toString p}${suffix}");
  every = proto: discovery.${proto} ++ remotePlay.${proto} ++ localNetworkGameTransfers.${proto};
in
{
  inherit discovery remotePlay localNetworkGameTransfers;
  published =
    publish "/udp" (every "udp" ++ builtins.concatMap expand (every "udpRanges"))
    ++ publish "" (every "tcp");
}
