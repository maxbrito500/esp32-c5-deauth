class StaEntry {
  final String mac;
  final int rssi;
  final int channel;
  final String bssid;

  const StaEntry({
    required this.mac,
    required this.rssi,
    required this.channel,
    required this.bssid,
  });
}
