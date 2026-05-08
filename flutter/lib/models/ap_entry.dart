class ApEntry {
  const ApEntry({
    required this.idx,
    required this.channel,
    required this.is5ghz,
    required this.rssi,
    required this.bssid,
    required this.ssid,
  });

  final int idx;
  final int channel;
  final bool is5ghz;
  final int rssi;
  final String bssid;
  final String ssid;
}
