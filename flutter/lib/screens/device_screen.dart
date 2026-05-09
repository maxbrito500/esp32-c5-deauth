import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/acl_entry.dart';
import '../models/ap_entry.dart';
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
  final _durationCtrl = TextEditingController(text: '30');
  static const _modes = ['broadcast', 'unicast', 'disassoc', 'authflood', 'mixed'];

  @override
  void initState() {
    super.initState();
    // Auto-scan if no networks are loaded yet — give the 'ls' response 2s to arrive first.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      final ctrl = context.read<DeviceController>();
      if (ctrl.aps.isEmpty && !ctrl.scanning && !ctrl.attacking) ctrl.scanWifi();
    });
  }

  @override
  void dispose() {
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final aps24 = ctrl.aps.where((a) => !a.is5ghz).toList();
    final aps5 = ctrl.aps.where((a) => a.is5ghz).toList();

    return Column(
      children: [
        _attackBar(context, ctrl),
        Expanded(
          child: ctrl.aps.isEmpty
              ? _emptyAps(ctrl)
              : ListView(
                  children: [
                    if (aps24.isNotEmpty) ...[
                      _bandHeader('2.4 GHz', Colors.teal),
                      ...aps24.map((ap) => _apTile(context, ctrl, ap)),
                    ],
                    if (aps5.isNotEmpty) ...[
                      _bandHeader('5 GHz', Colors.purple),
                      ...aps5.map((ap) => _apTile(context, ctrl, ap)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _attackBar(BuildContext context, DeviceController ctrl) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // Scan button
          OutlinedButton.icon(
            onPressed: ctrl.scanning ? null : ctrl.scanWifi,
            icon: ctrl.scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search, size: 18),
            label: Text(ctrl.scanning ? 'Scanning…' : 'Scan'),
          ),
          const SizedBox(width: 8),
          // Mode picker
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _modes.contains(ctrl.attackMode) ? ctrl.attackMode : 'broadcast',
                isExpanded: true,
                items: _modes
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: ctrl.attacking
                    ? null
                    : (v) { if (v != null) ctrl.setMode(v); },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Duration field
          SizedBox(
            width: 56,
            child: TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                  labelText: 'sec', isDense: true, border: OutlineInputBorder()),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !ctrl.attacking,
            ),
          ),
          const SizedBox(width: 8),
          // Start / Stop
          ctrl.attacking
              ? ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700),
                  onPressed: ctrl.stopAttack,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Stop'),
                )
              : ElevatedButton.icon(
                  onPressed: (ctrl.selected24Idx == null && ctrl.selected5Idx == null)
                      ? null
                      : () {
                          final secs = int.tryParse(_durationCtrl.text) ?? 30;
                          ctrl.startAttack(secs);
                        },
                  icon: const Icon(Icons.bolt, size: 18),
                  label: const Text('Deauth'),
                ),
        ],
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

  Widget _bandHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withAlpha(50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(150)),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _apTile(BuildContext context, DeviceController ctrl, ApEntry ap) {
    final isSelected = ap.is5ghz
        ? ctrl.selected5Idx == ap.idx
        : ctrl.selected24Idx == ap.idx;
    final color = ap.is5ghz ? Colors.purple : Colors.teal;
    return ListTile(
      dense: true,
      leading: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? color : Colors.transparent,
          border: Border.all(color: isSelected ? color : Colors.grey, width: 2),
        ),
      ),
      title: Text(
        ap.ssid.isNotEmpty ? ap.ssid : '(hidden)',
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text('ch ${ap.channel}  ${ap.bssid}  ${ap.rssi} dBm'),
      selected: isSelected,
      onTap: ctrl.attacking
          ? null
          : () {
              if (ap.is5ghz) {
                ctrl.selectAp5(ap.idx);
              } else {
                ctrl.selectAp24(ap.idx);
              }
            },
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

class _NukeTabState extends State<_NukeTab> {
  final _durationCtrl = TextEditingController(text: '60');
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    _durationCtrl.dispose();
    super.dispose();
  }

  void _syncTicker(bool isNuking) {
    if (isNuking && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!isNuking && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
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

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final isNuking = ctrl.attacking && ctrl.attackMode == 'nuke';
    final isOtherAttack = ctrl.attacking && !isNuking;
    final apCount = ctrl.aps.length;

    _syncTicker(isNuking);

    Duration remaining = Duration.zero;
    if (isNuking && ctrl.nukeStartedAt != null) {
      final elapsed = DateTime.now().difference(ctrl.nukeStartedAt!);
      final total = Duration(seconds: ctrl.nukeDurationSecs);
      final rem = total - elapsed;
      remaining = rem.isNegative ? Duration.zero : rem;
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status card
          Card(
            color: isNuking ? Colors.red.shade900.withAlpha(180) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                children: [
                  Icon(
                    isNuking ? Icons.bolt : Icons.bolt_outlined,
                    size: 36,
                    color: isNuking ? Colors.red.shade300 : Colors.grey,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNuking ? 'NUKING' : 'IDLE',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isNuking ? Colors.red.shade300 : Colors.grey,
                          ),
                        ),
                        if (isNuking) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${ctrl.nukeApCount} network${ctrl.nukeApCount == 1 ? '' : 's'} — all clients',
                            style: TextStyle(color: Colors.red.shade200),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Stops in ${_formatRemaining(remaining)}',
                            style: TextStyle(
                              color: remaining.inSeconds <= 10
                                  ? Colors.orange.shade300
                                  : Colors.grey.shade400,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ] else
                          Text(
                            '$apCount network${apCount == 1 ? '' : 's'} in range',
                            style: const TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (apCount == 0 && !isNuking)
            Card(
              color: Colors.amber.shade800.withAlpha(60),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'No networks scanned yet.\nGo to Networks tab and tap Scan first.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          if (isOtherAttack)
            Card(
              color: Colors.orange.shade800.withAlpha(60),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Another attack is running.\nStop it before launching Nuke.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          const Spacer(),

          if (!isNuking)
            TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (seconds)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.timer),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),

          const SizedBox(height: 16),

          SizedBox(
            height: 56,
            child: isNuking
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800),
                    onPressed: ctrl.stopAttack,
                    icon: const Icon(Icons.stop, size: 22),
                    label: const Text('Stop', style: TextStyle(fontSize: 17)),
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (apCount == 0 || isOtherAttack)
                          ? null
                          : Colors.red.shade700,
                    ),
                    onPressed: (apCount == 0 || isOtherAttack)
                        ? null
                        : () {
                            final secs = int.tryParse(_durationCtrl.text) ?? 60;
                            ctrl.nuke(secs);
                          },
                    icon: const Icon(Icons.bolt, size: 22),
                    label: const Text('Fire Nuke', style: TextStyle(fontSize: 17)),
                  ),
          ),
        ],
      ),
    );
  }
}
