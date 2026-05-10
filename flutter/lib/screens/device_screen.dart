import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/acl_entry.dart';
import '../models/ap_entry.dart';
import '../models/sta_entry.dart';
import '../services/device_controller.dart';
import 'settings_screen.dart';

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: const _DeviceView(),
    );
  }
}

class _DeviceView extends StatefulWidget {
  const _DeviceView();

  @override
  State<_DeviceView> createState() => _DeviceViewState();
}


class _DeviceViewState extends State<_DeviceView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<bool> _confirmDisconnect(BuildContext context) async {
    final ctrl = context.read<DeviceController>();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect?'),
        content: Text(
            'Disconnect from ${ctrl.conn.device.platformName.isNotEmpty ? ctrl.conn.device.platformName : "device"}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final name = ctrl.conn.device.platformName.isNotEmpty
        ? ctrl.conn.device.platformName
        : 'Connected';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmDisconnect(context) && context.mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          actions: [
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await _confirmDisconnect(context) && context.mounted) {
                  nav.pop();
                }
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              onSelected: (value) {
                final ctrl = context.read<DeviceController>();
                switch (value) {
                  case 'console':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _ConsoleScreen(controller: ctrl)));
                  case 'whitelist':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            _AclScreen(controller: ctrl, isWhitelist: true)));
                  case 'blacklist':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            _AclScreen(controller: ctrl, isWhitelist: false)));
                  case 'settings':
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'console', child: Text('Console')),
                PopupMenuItem(value: 'whitelist', child: Text('Whitelist')),
                PopupMenuItem(value: 'blacklist', child: Text('Blacklist')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            tabs: [
              const Tab(icon: Icon(Icons.wifi), text: 'Networks'),
              Tab(icon: Icon(Icons.bolt, color: Colors.red.shade400), text: 'Nuke'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: const [
            _NetworksTab(),
            _NukeTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Console / ACL push-route screens ────────────────────────────────────────

class _ConsoleScreen extends StatelessWidget {
  const _ConsoleScreen({required this.controller});
  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Scaffold(
        appBar: AppBar(title: const Text('Console')),
        body: const _ConsoleTab(),
      ),
    );
  }
}

class _AclScreen extends StatelessWidget {
  const _AclScreen({required this.controller, required this.isWhitelist});
  final DeviceController controller;
  final bool isWhitelist;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: controller,
      child: Scaffold(
        appBar: AppBar(title: Text(isWhitelist ? 'Whitelist' : 'Blacklist')),
        body: _AclTab(isWhitelist: isWhitelist),
      ),
    );
  }
}

// ─── Networks tab ────────────────────────────────────────────────────────────

class _NetworksTab extends StatefulWidget {
  const _NetworksTab();

  @override
  State<_NetworksTab> createState() => _NetworksTabState();
}

class _NetworksTabState extends State<_NetworksTab> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final ctrl = context.read<DeviceController>();
      if (ctrl.aps.isEmpty && !ctrl.scanning && !ctrl.attacking) ctrl.scanWifi();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool isAttacking) {
    if (isAttacking && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isAttacking && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final isAttacking = ctrl.attacking && ctrl.attackMode != 'nuke';

    _syncTicker(isAttacking);

    final sorted = [...ctrl.aps]..sort((a, b) {
        final sc = a.ssid.toLowerCase().compareTo(b.ssid.toLowerCase());
        if (sc != 0) return sc;
        if (!a.is5ghz && b.is5ghz) return -1;
        if (a.is5ghz && !b.is5ghz) return 1;
        return 0;
      });

    return Column(
      children: [
        _toolbar(context, ctrl),
        if (isAttacking) _attackStatus(ctrl),
        Expanded(
          child: ctrl.aps.isEmpty
              ? _emptyAps(ctrl)
              : ListView.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _apTile(context, ctrl, sorted[i]),
                ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context, DeviceController ctrl) {
    final isAttacking = ctrl.attacking && ctrl.attackMode != 'nuke';
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: (ctrl.scanning || isAttacking) ? null : ctrl.scanWifi,
            icon: ctrl.scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search, size: 18),
            label: Text(ctrl.scanning ? 'Scanning…' : 'Scan'),
          ),
          const Spacer(),
          if (isAttacking)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: ctrl.stopAttack,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop'),
            )
          else
            ElevatedButton.icon(
              onPressed: ctrl.selectedIdxs.isEmpty
                  ? null
                  : ctrl.startAttack,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Deauth'),
            ),
        ],
      ),
    );
  }

  Widget _attackStatus(DeviceController ctrl) {
    Duration elapsed = Duration.zero;
    if (ctrl.attackStartedAt != null) {
      elapsed = DateTime.now().difference(ctrl.attackStartedAt!);
    }
    return Container(
      width: double.infinity,
      color: Colors.red.shade900.withAlpha(180),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Attacking ${ctrl.attackAps} network${ctrl.attackAps == 1 ? '' : 's'}'
        '   ${_formatElapsed(elapsed)} elapsed',
        style: TextStyle(color: Colors.red.shade200, fontSize: 13),
      ),
    );
  }

  Widget _emptyAps(DeviceController ctrl) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('No networks — tap Scan'),
          const SizedBox(height: 12),
          if (ctrl.scanning) const CircularProgressIndicator(),
        ],
      ),
    );
  }

  Widget _apTile(BuildContext context, DeviceController ctrl, ApEntry ap) {
    final isSelected = ctrl.selectedIdxs.contains(ap.idx);
    final bandColor = ap.is5ghz ? Colors.purple : Colors.teal;
    final isAttacking = ctrl.attacking;
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: isSelected,
        activeColor: bandColor,
        onChanged: isAttacking ? null : (_) => ctrl.toggleAp(ap.idx),
      ),
      title: Text(ap.ssid.isNotEmpty ? ap.ssid : '(hidden)'),
      subtitle: Row(children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: bandColor.withAlpha(40),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: bandColor.withAlpha(120)),
          ),
          child: Text(ap.is5ghz ? '5 GHz' : '2.4 GHz',
              style: TextStyle(color: bandColor, fontSize: 11)),
        ),
        Text('ch ${ap.channel}   ${ap.rssi} dBm'),
      ]),
      selected: isSelected,
      onTap: isAttacking ? null : () => ctrl.toggleAp(ap.idx),
    );
  }
}

// ─── ACL tab (Whitelist / Blacklist) ─────────────────────────────────────────

class _AclTab extends StatefulWidget {
  const _AclTab({required this.isWhitelist});

  final bool isWhitelist;

  @override
  State<_AclTab> createState() => _AclTabState();
}

class _AclTabState extends State<_AclTab> {
  final _macCtrl = TextEditingController();
  String _kind = 'auto';

  @override
  void dispose() {
    _macCtrl.dispose();
    super.dispose();
  }

  List<AclEntry> _list(DeviceController ctrl) =>
      widget.isWhitelist ? ctrl.whitelist : ctrl.blacklist;

  Future<void> _add(DeviceController ctrl) async {
    final mac = _macCtrl.text.trim();
    if (mac.isEmpty) return;
    if (widget.isWhitelist) {
      await ctrl.addToWhitelist(mac, _kind);
    } else {
      await ctrl.addToBlacklist(mac, _kind);
    }
    _macCtrl.clear();
  }

  Future<void> _remove(DeviceController ctrl, String mac) async {
    if (widget.isWhitelist) {
      await ctrl.removeFromWhitelist(mac);
    } else {
      await ctrl.removeFromBlacklist(mac);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final entries = _list(ctrl);
    final accent = widget.isWhitelist ? Colors.teal : Colors.red;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _macCtrl,
                  decoration: InputDecoration(
                    labelText: 'MAC address (XX:XX:XX:XX:XX:XX)',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                        widget.isWhitelist ? Icons.check_circle_outline : Icons.block,
                        color: accent),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f:]')),
                    LengthLimitingTextInputFormatter(17),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _kind,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('auto')),
                    DropdownMenuItem(value: 'bssid', child: Text('bssid')),
                    DropdownMenuItem(value: 'sta', child: Text('sta')),
                  ],
                  onChanged: (v) { if (v != null) setState(() => _kind = v); },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _add(ctrl),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text('${widget.isWhitelist ? "Whitelist" : "Blacklist"} is empty',
                      style: const TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                          widget.isWhitelist ? Icons.check_circle_outline : Icons.block,
                          color: accent),
                      title: Text(e.mac,
                          style: const TextStyle(fontFamily: 'monospace')),
                      subtitle: Text(e.kind),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove',
                        onPressed: () => _remove(ctrl, e.mac),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Console tab ─────────────────────────────────────────────────────────────

class _ConsoleTab extends StatefulWidget {
  const _ConsoleTab();

  @override
  State<_ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<_ConsoleTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String _prevLog = '';

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(BuildContext context, String cmd) async {
    cmd = cmd.trim();
    if (cmd.isEmpty) return;
    final ctrl = context.read<DeviceController>();
    await ctrl.conn.send(cmd);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    if (ctrl.rawLog != _prevLog) {
      _prevLog = ctrl.rawLog;
      _scrollToBottom();
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  ctrl.rawLog,
                  style: const TextStyle(
                    color: Color(0xFF8FFF8F),
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(
                    hintText: 'raw command',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) => _send(context, v),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\n')),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _send(context, _input.text),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Send'),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Clear log',
                icon: const Icon(Icons.clear_all),
                onPressed: () => context.read<DeviceController>().clearLog(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


// ─── Nuke tab ─────────────────────────────────────────────────────────────────
class _NukeTab extends StatefulWidget {
  const _NukeTab();

  @override
  State<_NukeTab> createState() => _NukeTabState();
}

class _NukeTabState extends State<_NukeTab>
    with SingleTickerProviderStateMixin {
  final _durationCtrl = TextEditingController(text: '60');
  Timer? _countdownTicker;
  late AnimationController _radarCtrl;
  Offset? _inputPos;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _durationCtrl.dispose();
    _radarCtrl.dispose();
    super.dispose();
  }

  void _syncCountdown(bool isNuking) {
    if (isNuking && _countdownTicker == null) {
      _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isNuking && _countdownTicker != null) {
      _countdownTicker!.cancel();
      _countdownTicker = null;
    }
  }

  String _formatRemaining(Duration d) {
    if (d <= Duration.zero) return '0s';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _fmtPkts(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final isNuking = ctrl.attacking && ctrl.attackMode == 'nuke';
    final isOtherAttack = ctrl.attacking && !isNuking;
    final apCount = ctrl.aps.length;

    _syncCountdown(isNuking);

    Duration remaining = Duration.zero;
    if (isNuking && ctrl.nukeStartedAt != null) {
      final elapsed = DateTime.now().difference(ctrl.nukeStartedAt!);
      final total = Duration(seconds: ctrl.nukeDurationSecs);
      final rem = total - elapsed;
      remaining = rem.isNegative ? Duration.zero : rem;
    }

    final statusText = isNuking
        ? 'NUKING · ${ctrl.nukeApCount} NETS'
        : apCount == 0
            ? 'NO TARGETS'
            : '$apCount TARGETS IN RANGE';
    final infoText = isNuking
        ? '${_formatRemaining(remaining)} · ${_fmtPkts(ctrl.nukePkts)} frames'
        : null;

    return Column(
      children: [
        // Radar — fills all available vertical space
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: MouseRegion(
              onHover:  (e) => setState(() => _inputPos = e.localPosition),
              onExit:   (_) => setState(() => _inputPos = null),
              child: GestureDetector(
                onTapDown: (e) => setState(() => _inputPos = e.localPosition),
                child: AnimatedBuilder(
                  animation: _radarCtrl,
                  builder: (_, _) => CustomPaint(
                    painter: _RadarPainter(
                      sweepAngle: _radarCtrl.value * 2 * math.pi,
                      aps: ctrl.aps,
                      isNuking: isNuking,
                      statusText: statusText,
                      infoText: infoText,
                      inputPos: _inputPos,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Conflict warning
        if (isOtherAttack)
          Container(
            color: Colors.orange.shade900.withAlpha(120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: const Text(
              'Stop the current attack before launching Nuke.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),

        // Controls row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            children: [
              if (!isNuking) ...[
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Seconds',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: isNuking
                      ? ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade800),
                          onPressed: ctrl.stopAttack,
                          icon: const Icon(Icons.stop, size: 20),
                          label: const Text('Stop Nuke'),
                        )
                      : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                (apCount == 0 || isOtherAttack)
                                    ? null
                                    : Colors.red.shade700,
                          ),
                          onPressed: (apCount == 0 || isOtherAttack)
                              ? null
                              : () {
                                  final secs =
                                      int.tryParse(_durationCtrl.text) ?? 60;
                                  ctrl.nuke(secs);
                                },
                          icon: const Icon(Icons.bolt, size: 20),
                          label: const Text('Fire Nuke'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Military radar CustomPainter ────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweepAngle,
    required this.aps,
    required this.isNuking,
    required this.statusText,
    this.infoText,
    this.inputPos,
  });

  final double sweepAngle;
  final List<ApEntry> aps;
  final bool isNuking;
  final String statusText;
  final String? infoText;
  final Offset? inputPos;

  static const _bg       = Color(0xFF010D01);
  static const _ring     = Color(0xFF0C3A0C);
  static const _phosphor = Color(0xFF39FF14);
  static const _dimGreen = Color(0xFF1B5C1B);
  static const _targetC  = Color(0xFFFF4800);
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = math.min(cx, cy) - 2;

    // Dynamic range: farthest detected AP sits at ~80% of radar edge (25% headroom)
    double maxM = 10.0;
    for (final ap in aps) {
      final m = math.pow(10.0, (-45.0 - ap.rssi) / 27.0).toDouble();
      if (m > maxM) maxM = m;
    }
    maxM = (maxM * 1.25).clamp(10.0, 200.0);

    // Group APs by normalized SSID so same-router networks share a neighborhood.
    // Within each group, sort 2.4 GHz first then 5 GHz and fan by ~5° per member.
    final Map<String, List<ApEntry>> groups = {};
    for (final ap in aps) {
      groups.putIfAbsent(_normSsid(ap.ssid), () => []).add(ap);
    }
    for (final g in groups.values) {
      g.sort((a, b) => (a.is5ghz ? 1 : 0).compareTo(b.is5ghz ? 1 : 0));
    }
    const fanStep = 0.085; // ~4.9° per member
    final Map<String, double> apAngles = {};
    for (final entry in groups.entries) {
      final base = _groupAngle(entry.key);
      final members = entry.value;
      for (int i = 0; i < members.length; i++) {
        apAngles[members[i].bssid] =
            base + (i - (members.length - 1) / 2.0) * fanStep;
      }
    }

    // Clip everything inside the circle
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: r)));

    // Background
    canvas.drawPaint(Paint()..color = _bg);

    // Concentric range rings
    final ringPaint = Paint()
      ..color = _ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, r * i / 4, ringPaint);
    }

    // Cross-hairs (horizontal, vertical, diagonals)
    final xhPaint = Paint()
      ..color = _ring
      ..strokeWidth = 0.4;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), xhPaint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), xhPaint);
    final diag = r / math.sqrt2;
    canvas.drawLine(
        Offset(cx - diag, cy - diag), Offset(cx + diag, cy + diag), xhPaint);
    canvas.drawLine(
        Offset(cx + diag, cy - diag), Offset(cx - diag, cy + diag), xhPaint);

    // Azimuth tick marks every 30°
    final tickPaint = Paint()
      ..color = _dimGreen
      ..strokeWidth = 0.9;
    for (int i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        Offset(cx + (r - 8) * math.cos(a), cy + (r - 8) * math.sin(a)),
        Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
        tickPaint,
      );
    }

    // Phosphor sweep trail
    const trailSpan = math.pi * 0.65; // ~117° of fading trail
    final trailRect = Rect.fromCircle(center: center, radius: r);
    final trailPath = Path()
      ..moveTo(cx, cy)
      ..arcTo(trailRect, sweepAngle - trailSpan, trailSpan, false)
      ..close();
    canvas.drawPath(
      trailPath,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepAngle - trailSpan,
          endAngle: sweepAngle,
          colors: [Colors.transparent, _phosphor.withValues(alpha: 0.22)],
          tileMode: TileMode.clamp,
        ).createShader(trailRect),
    );

    // Find nearest AP to cursor/tap for highlight (hit radius 30px)
    String? highlightBssid;
    if (inputPos != null) {
      double best = 30.0;
      for (final ap in aps) {
        final a = apAngles[ap.bssid]!;
        final dr = _apRadius(ap.rssi, r, maxM);
        final d = (Offset(cx + dr * math.cos(a), cy + dr * math.sin(a)) - inputPos!).distance;
        if (d < best) { best = d; highlightBssid = ap.bssid; }
      }
    }

    // AP dots with ping glow
    for (final ap in aps) {
      _paintAp(canvas, ap, apAngles[ap.bssid]!, center, r, maxM, ap.bssid == highlightBssid);
    }

    // Sweep line (on top of everything)
    canvas.drawLine(
      center,
      Offset(cx + r * math.cos(sweepAngle), cy + r * math.sin(sweepAngle)),
      Paint()
        ..color = _phosphor.withValues(alpha: 0.92)
        ..strokeWidth = 1.5,
    );

    // Bullseye at center (the deauther)
    canvas.drawCircle(center, 2.5, Paint()..color = _phosphor);
    canvas.drawCircle(
        center,
        6,
        Paint()
          ..color = _phosphor.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);

    canvas.restore(); // end clip

    // Range labels and status text are drawn outside the clip
    _paintRangeLabels(canvas, center, r, maxM);
    _paintStatus(canvas, center, r);
  }

  void _paintAp(Canvas canvas, ApEntry ap, double angle, Offset center,
      double maxR, double maxM, bool highlighted) {
    final dotR  = _apRadius(ap.rssi, maxR, maxM);
    final pos   = Offset(
      center.dx + dotR * math.cos(angle),
      center.dy + dotR * math.sin(angle),
    );

    final age  = _pingAge(angle);
    final glow = math.max(0.0, 1.0 - age / 3.2);

    final col = isNuking ? _targetC : _phosphor;
    final dim = isNuking ? _targetC.withValues(alpha: 0.32) : _dimGreen;

    // Highlight halo (hover / tap)
    if (highlighted) {
      canvas.drawCircle(
        pos, 16,
        Paint()
          ..color = col.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Ping glow halo
    if (glow > 0.04) {
      canvas.drawCircle(
        pos,
        10 * glow,
        Paint()
          ..color = col.withValues(alpha: 0.18 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // Core dot — larger when highlighted
    canvas.drawCircle(pos, highlighted ? 4.5 : 2.5,
        Paint()..color = highlighted ? col : (glow > 0.04 ? col : dim));

    // Label: "SSID · dist" — bigger and fully bright when highlighted
    final dist   = _fmtDist(ap.rssi);
    final ssid   = ap.ssid.length > 18 ? '${ap.ssid.substring(0, 16)}..' : ap.ssid;
    final label  = '$ssid · $dist';
    final fSize  = highlighted ? 14.0 : 11.0;
    final fAlpha = highlighted ? 1.0 : (glow > 0.04 ? 0.92 + 0.08 * glow : 0.72);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: (highlighted ? col : (glow > 0.04 ? col : dim))
              .withValues(alpha: fAlpha),
          fontSize: fSize,
          fontWeight: highlighted ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 160);
    tp.paint(canvas, Offset(pos.dx + 6, pos.dy - tp.height / 2));
  }

  static String _fmtDist(int rssi) {
    final m = math.pow(10.0, (-45.0 - rssi) / 27.0).toDouble();
    if (m < 1.0) return '<1m';
    if (m < 10.0) return '${m.toStringAsFixed(1)}m';
    return '${m.round()}m';
  }

  void _paintRangeLabels(Canvas canvas, Offset center, double r, double maxM) {
    final labels = [
      '${(maxM / 4).round()}m',
      '${(maxM / 2).round()}m',
      '${(maxM * 3 / 4).round()}m',
      '${maxM.round()}m',
    ];
    for (int i = 0; i < 4; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(color: _dimGreen, fontSize: 7),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        center.dx + 3,
        center.dy - (i + 1) / 4.0 * r - tp.height / 2,
      ));
    }
  }

  void _paintStatus(Canvas canvas, Offset center, double r) {
    final left = center.dx - r + 10;
    final top  = center.dy - r + 10;

    final primaryColor =
        isNuking ? _targetC.withValues(alpha: 0.9) : _phosphor.withValues(alpha: 0.72);

    final tp1 = TextPainter(
      text: TextSpan(
        text: statusText,
        style: TextStyle(
          color: primaryColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(left, top));

    if (infoText != null) {
      final tp2 = TextPainter(
        text: TextSpan(
          text: infoText,
          style: TextStyle(
              color: _phosphor.withValues(alpha: 0.55), fontSize: 8.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp2.paint(canvas, Offset(left, top + tp1.height + 3));
    }
  }

  // Strip common band/variant suffixes so same-router SSIDs share a group key.
  // e.g. "HomeNet_5G", "HomeNet-5GHz", "HomeNet_EXT" → "HomeNet"
  static final _suffixRe = RegExp(
      r'[-_ ](5g(hz)?|2\.?4g(hz)?|2g(hz)?|6g(hz)?|5|2|ext(ender)?|plus|fast|iot|mesh|guest)$',
      caseSensitive: false);
  static String _normSsid(String ssid) {
    String s = ssid.trim();
    String prev;
    do {
      prev = s;
      s = s.replaceAll(_suffixRe, '').trim();
    } while (s != prev && s.length > 2);
    return s.toLowerCase();
  }

  // Stable angle derived from the normalized SSID via FNV-1a hash
  static double _groupAngle(String normSsid) {
    int h = 2166136261;
    for (final c in normSsid.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return (h / 0xFFFFFFFF) * 2 * math.pi;
  }

  // Radial distance on the radar canvas based on RSSI
  static double _apRadius(int rssi, double maxR, double maxM) {
    // Log-distance: txPower=-45 dBm, n=2.7 → exponent divisor ≈ 27
    final m = math.pow(10.0, (-45.0 - rssi) / 27.0).toDouble();
    return (m.clamp(1.0, maxM) / maxM) * maxR;
  }

  // Seconds since the sweep last passed this angle (0 … 30 s)
  double _pingAge(double dotAngle) {
    final sa = ((sweepAngle % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
    final da = ((dotAngle   % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
    return ((sa - da + 2 * math.pi) % (2 * math.pi)) / (2 * math.pi) * 30.0;
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}
