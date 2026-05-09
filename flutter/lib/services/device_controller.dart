import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/acl_entry.dart';
import '../models/ap_entry.dart';
import 'nus_client.dart';

class DeviceController extends ChangeNotifier {
  DeviceController(this.conn) {
    _sub = conn.incoming.listen(_onChunk);
    conn.send('status');
    conn.send('ls');
    conn.send('sel ls');
    conn.send('wl ls');
    conn.send('bl ls');
  }

  final NusConnection conn;
  StreamSubscription<String>? _sub;

  List<ApEntry> aps = const [];
  List<AclEntry> whitelist = const [];
  List<AclEntry> blacklist = const [];
  Set<int> selectedIdxs = {};
  bool attacking = false;
  String attackMode = 'mixed';
  bool scanning = false;
  String rawLog = '';
  DateTime? _lastScanTime;

  // Regular attack state
  DateTime? attackStartedAt;
  int attackAps = 0;

  // Nuke state
  DateTime? nukeStartedAt;
  int nukeDurationSecs = 0;
  int nukeApCount = 0;

  bool get scanIsStale {
    if (aps.isEmpty) return true;
    if (_lastScanTime == null) return true;
    return DateTime.now().difference(_lastScanTime!) > const Duration(minutes: 5);
  }

  // Parse state
  final StringBuffer _buf = StringBuffer();
  bool _inAps = false;
  bool _inWl = false;
  bool _inBl = false;
  final List<ApEntry> _tmpAps = [];
  final List<AclEntry> _tmpWl = [];
  final List<AclEntry> _tmpBl = [];

  static final _reNuke    = RegExp(r'^nuke: (\d+)s\s+aps=(\d+)');
  static final _reAttack  = RegExp(r'^attack: (\d+)s\s+aps=(\d+)');
  static final _reSelLine = RegExp(r'^sel:([ \d]*)$');
  static final _reSelToggle = RegExp(r'^sel: (\d+) (on|off)$');
  static final _reAp = RegExp(
      r'^\s*(\d+)\s+(\d+)\s+(2\.4GHz|5GHz)\s+(-?\d+)\s+'
      r'([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s+(.*?)\s*$');
  static final _reWl = RegExp(
      r'^wl\s+([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s+(auto|bssid|sta)');
  static final _reBl = RegExp(
      r'^bl\s+([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s+(auto|bssid|sta)');
  static final _reMode = RegExp(r'^mode: (\w+)$');

  void _onChunk(String chunk) {
    rawLog += chunk;
    _buf.write(chunk);
    final s = _buf.toString();
    final parts = s.split('\n');
    _buf.clear();
    if (!s.endsWith('\n')) {
      _buf.write(parts.removeLast());
    } else {
      parts.removeLast();
    }
    for (final p in parts) {
      _parseLine(p.replaceAll('\r', '').trim());
    }
    notifyListeners();
  }

  void _commitAps() {
    aps = List.unmodifiable(_tmpAps.toList());
    _tmpAps.clear();
    _inAps = false;
  }

  void _commitWl() {
    whitelist = List.unmodifiable(_tmpWl.toList());
    _tmpWl.clear();
    _inWl = false;
  }

  void _commitBl() {
    blacklist = List.unmodifiable(_tmpBl.toList());
    _tmpBl.clear();
    _inBl = false;
  }

  void _parseLine(String line) {
    if (line.isEmpty) return;

    // AP table header
    if (line.startsWith('idx  ch  band')) {
      _commitAps();
      _inAps = true;
      return;
    }

    // AP data row
    if (_inAps) {
      final m = _reAp.firstMatch(line);
      if (m != null) {
        _tmpAps.add(ApEntry(
          idx: int.parse(m.group(1)!),
          channel: int.parse(m.group(2)!),
          is5ghz: m.group(3) == '5GHz',
          rssi: int.parse(m.group(4)!),
          bssid: m.group(5)!.toUpperCase(),
          ssid: m.group(6)!,
        ));
        return;
      }
      _commitAps();
    }

    // WL row
    final wm = _reWl.firstMatch(line);
    if (wm != null) {
      if (!_inWl) { _tmpWl.clear(); _inWl = true; }
      _tmpWl.add(AclEntry(mac: wm.group(1)!.toUpperCase(), kind: wm.group(2)!));
      return;
    }

    // BL row
    final bm = _reBl.firstMatch(line);
    if (bm != null) {
      if (!_inBl) { _tmpBl.clear(); _inBl = true; }
      _tmpBl.add(AclEntry(mac: bm.group(1)!.toUpperCase(), kind: bm.group(2)!));
      return;
    }

    // Empty list sentinels
    if (line == '(wl empty)') { _tmpWl.clear(); _commitWl(); return; }
    if (line == '(bl empty)') { _tmpBl.clear(); _commitBl(); return; }

    // Commit WL/BL if we were collecting and hit something else
    if (_inWl) _commitWl();
    if (_inBl) _commitBl();

    // Sel toggle response: "sel: 3 on" / "sel: 3 off"
    final st = _reSelToggle.firstMatch(line);
    if (st != null) {
      final idx = int.parse(st.group(1)!);
      if (st.group(2) == 'on') {
        selectedIdxs = {...selectedIdxs, idx};
      } else {
        selectedIdxs = selectedIdxs.where((i) => i != idx).toSet();
      }
      return;
    }

    // Sel list response: "sel: 0 3 5" or "sel: (empty)"
    final sl = _reSelLine.firstMatch(line);
    if (sl != null) {
      final nums = sl.group(1)!.trim().split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();
      selectedIdxs = nums;
      return;
    }

    // Scan lifecycle
    if (line == 'scan: start (dual-band)') { scanning = true; return; }
    if (line.startsWith('scan: ') &&
        (RegExp(r'scan: \d+ APs').hasMatch(line) ||
         line.startsWith('scan: no APs') ||
         line.startsWith('scan: failed'))) {
      scanning = false;
      selectedIdxs = {};  // indices shift after each scan
      if (RegExp(r'scan: \d+ APs').hasMatch(line)) {
        _lastScanTime = DateTime.now();
        conn.send('ls');
        conn.send('sel ls');
      }
      return;
    }
    if (line == '(no APs — run `scan` first)') {
      aps = const [];
      return;
    }

    // Legacy t24/t5 confirmation (still used by sniff workflow)
    if (line.startsWith('t24:') || line.startsWith('t5:')) return;
    if (line == 'clear: selection reset') {
      selectedIdxs = {};
      return;
    }

    // Nuke progress
    final nm = _reNuke.firstMatch(line);
    if (nm != null) {
      nukeApCount = int.parse(nm.group(2)!);
      return;
    }

    // Regular attack progress: "attack: 4s  aps=2  total=1234  pps=308"
    final am = _reAttack.firstMatch(line);
    if (am != null) {
      attackAps = int.parse(am.group(2)!);
      return;
    }

    // Attack state
    if (line.startsWith('attack: start mode=')) {
      attacking = true;
      final mm = RegExp(r'mode=(\w+)').firstMatch(line);
      if (mm != null) attackMode = mm.group(1)!;
      if (attackMode == 'nuke') {
        nukeStartedAt = DateTime.now();
        final dm = RegExp(r'duration=(\d+)s').firstMatch(line);
        if (dm != null) nukeDurationSecs = int.parse(dm.group(1)!);
        final apm = RegExp(r'aps=(\d+)').firstMatch(line);
        if (apm != null) nukeApCount = int.parse(apm.group(1)!);
      } else {
        attackStartedAt = DateTime.now();
        final apm = RegExp(r'aps=(\d+)').firstMatch(line);
        if (apm != null) attackAps = int.parse(apm.group(1)!);
      }
      return;
    }
    if (line.startsWith('attack: stopped') ||
        line == 'attack: stop requested' ||
        line == 'attack: not running') {
      attacking = false;
      nukeStartedAt = null;
      attackStartedAt = null;
      return;
    }
    if (line.startsWith('status: idle')) {
      attacking = false;
      nukeStartedAt = null;
      attackStartedAt = null;
      return;
    }
    if (line.startsWith('status: running')) {
      attacking = true;
      final mm = RegExp(r'mode=(\w+)').firstMatch(line);
      if (mm != null) attackMode = mm.group(1)!;
      if (attackMode != 'nuke' && attackStartedAt == null) {
        attackStartedAt = DateTime.now();
      }
      final apm = RegExp(r'aps=(\d+)').firstMatch(line);
      if (apm != null) attackAps = int.parse(apm.group(1)!);
      return;
    }

    // Mode change confirmation
    final mm = _reMode.firstMatch(line);
    if (mm != null) { attackMode = mm.group(1)!; return; }
  }

  Future<void> scanWifi() async {
    scanning = true;
    notifyListeners();
    await conn.send('scan');
  }

  Future<void> toggleAp(int idx) => conn.send('sel $idx');

  Future<void> clearSelection() => conn.send('clear');

  Future<void> startAttack() => conn.send('start');

  Future<void> stopAttack() => conn.send('stop');

  Future<void> nuke(int secs) => conn.send('nuke $secs');

  Future<void> addToWhitelist(String mac, [String kind = 'auto']) async {
    await conn.send('wl add $mac $kind');
    _tmpWl.clear();
    await conn.send('wl ls');
  }

  Future<void> removeFromWhitelist(String mac) async {
    await conn.send('wl rm $mac');
    _tmpWl.clear();
    await conn.send('wl ls');
  }

  Future<void> addToBlacklist(String mac, [String kind = 'auto']) async {
    await conn.send('bl add $mac $kind');
    _tmpBl.clear();
    await conn.send('bl ls');
  }

  Future<void> removeFromBlacklist(String mac) async {
    await conn.send('bl rm $mac');
    _tmpBl.clear();
    await conn.send('bl ls');
  }

  void clearLog() {
    rawLog = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
