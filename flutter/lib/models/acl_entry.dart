class AclEntry {
  const AclEntry({required this.mac, required this.kind});

  final String mac;
  final String kind; // auto | bssid | sta
}
