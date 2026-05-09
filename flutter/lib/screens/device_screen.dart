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
    _tabs = TabController(length: 3, vsync: this);
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
              const Tab(icon: Icon(Icons.devices), text: 'Devices'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: const [
            _NetworksTab(),
            _NukeTab(),
            _DevicesTab(),
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

// ─── Devices tab ─────────────────────────────────────────────────────────────

class _DevicesTab extends StatefulWidget {
  const _DevicesTab();

  @override
  State<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<_DevicesTab> {
  static const Map<String, String> _oui = {
    // Apple
    '001AE3': 'Apple', '001124': 'Apple', '0016CB': 'Apple', '001EC2': 'Apple',
    '002241': 'Apple', '00236C': 'Apple', '0025BC': 'Apple', '0050E4': 'Apple',
    '041552': 'Apple', '04489A': 'Apple', '087045': 'Apple', '0C3E9F': 'Apple',
    '14109F': 'Apple', '183451': 'Apple', '1C36BB': 'Apple', '1CE62B': 'Apple',
    '203CAE': 'Apple', '24A074': 'Apple', '286AB8': 'Apple', '28CFE9': 'Apple',
    '2C1F23': 'Apple', '34C059': 'Apple', '380F4A': 'Apple', '3C0754': 'Apple',
    '403CFC': 'Apple', '4C7403': 'Apple', '501AC5': 'Apple', '58B035': 'Apple',
    '5C8D4E': 'Apple', '60F445': 'Apple', '68AE20': 'Apple', '6C4008': 'Apple',
    '748D08': 'Apple', '7831C1': 'Apple', '84788B': 'Apple', '9027E4': 'Apple',
    'A0D795': 'Apple', 'A45E60': 'Apple', 'A8FAD8': 'Apple', 'AC3C0B': 'Apple',
    'B018D1': 'Apple', 'B44BD3': 'Apple', 'B853AC': 'Apple', 'BC9FEF': 'Apple',
    'C42C03': 'Apple', 'C82A14': 'Apple', 'D0034B': 'Apple', 'D4F46F': 'Apple',
    'D81D72': 'Apple', 'E0B9BA': 'Apple', 'E4E4AB': 'Apple', 'EC3586': 'Apple',
    'F01898': 'Apple', 'F45C89': 'Apple', 'F81EDF': 'Apple', 'FC253F': 'Apple',
    'FCFC48': 'Apple',
    // Samsung
    '001599': 'Samsung', '0017C9': 'Samsung', '0021D2': 'Samsung', '002339': 'Samsung',
    '0024E9': 'Samsung', '002566': 'Samsung', '08ECA9': 'Samsung', '1065EF': 'Samsung',
    '14499A': 'Samsung', '188350': 'Samsung', '1C627A': 'Samsung', '2C0E3D': 'Samsung',
    '306F6E': 'Samsung', '38D547': 'Samsung', '3CB72B': 'Samsung', '40B0FA': 'Samsung',
    '4CD95E': 'Samsung', '509EA7': 'Samsung', '5CF6DC': 'Samsung', '6C2F2C': 'Samsung',
    '740D4E': 'Samsung', '84254E': 'Samsung', '8C77B3': 'Samsung', '9069B5': 'Samsung',
    '942BD3': 'Samsung', '9802D8': 'Samsung', 'A4EB03': 'Samsung', 'B47C9C': 'Samsung',
    'BC7738': 'Samsung', 'C4508A': 'Samsung', 'C8A958': 'Samsung', 'D0170C': 'Samsung',
    'D45087': 'Samsung', 'D8D1CB': 'Samsung', 'E09C89': 'Samsung', 'E4E0C5': 'Samsung',
    'EC1F72': 'Samsung', 'F04E76': 'Samsung', 'F47B5E': 'Samsung',
    // Google
    '001A11': 'Google', '08597E': 'Google', '1C9162': 'Google', '20DF3B': 'Google',
    '3C5AB4': 'Google', '54607E': 'Google', '6C5AB5': 'Google', 'A47733': 'Google',
    'F41041': 'Google',
    // Amazon
    '0026B9': 'Amazon', '34D270': 'Amazon', '40B4CD': 'Amazon', '44650D': 'Amazon',
    '68037B': 'Amazon', '74C246': 'Amazon', '78E103': 'Amazon', 'A002DC': 'Amazon',
    'CC9EF1': 'Amazon', 'F0D261': 'Amazon',
    // Intel
    '001578': 'Intel', '001BEA': 'Intel', '002130': 'Intel', '002248': 'Intel',
    '0024D6': 'Intel', '4CE17D': 'Intel', '5CF7D6': 'Intel', '748777': 'Intel',
    '748A20': 'Intel', '786F05': 'Intel', '80B888': 'Intel', '886B6E': 'Intel',
    '9CB654': 'Intel', 'A4C494': 'Intel', 'D4BE13': 'Intel', 'F8D111': 'Intel',
    // Espressif
    '240AC4': 'Espressif', '3C71BF': 'Espressif', '3C8461': 'Espressif',
    '48E72B': 'Espressif', '503EAA': 'Espressif', '54527E': 'Espressif',
    '7CDFA1': 'Espressif', '840D8E': 'Espressif', 'A0207B': 'Espressif',
    'B4E62D': 'Espressif', 'C44F33': 'Espressif', 'D8BFC0': 'Espressif',
    'E09806': 'Espressif', 'EC94CB': 'Espressif', 'F4CFA2': 'Espressif',
    // Raspberry Pi
    'B827EB': 'Raspberry Pi', 'DCA632': 'Raspberry Pi', 'E45F01': 'Raspberry Pi',
    // Microsoft
    '003080': 'Microsoft', '0050F2': 'Microsoft', '001DD8': 'Microsoft',
    '002421': 'Microsoft', '485B0F': 'Microsoft', '601302': 'Microsoft',
    '7C1AEA': 'Microsoft', '985FD3': 'Microsoft',
    // Sony
    '001A80': 'Sony', '001EE3': 'Sony', '002148': 'Sony', '0022A9': 'Sony',
    '0024BE': 'Sony', '08D4A8': 'Sony', '402079': 'Sony', '1CC1DE': 'Sony',
    '2CCA68': 'Sony', '3C0771': 'Sony', '40B89A': 'Sony', '540A40': 'Sony',
    'A0E451': 'Sony', 'B87724': 'Sony',
    // Nintendo
    '002659': 'Nintendo', '0009BF': 'Nintendo', '000FC3': 'Nintendo',
    '041693': 'Nintendo', '0498C7': 'Nintendo', '2C10C1': 'Nintendo',
    '40F407': 'Nintendo', '5C521D': 'Nintendo', '7C3C3F': 'Nintendo',
    '8C56C5': 'Nintendo', '9458CB': 'Nintendo', 'A45C27': 'Nintendo',
    'E00C7F': 'Nintendo', 'E84ECE': 'Nintendo',
    // Xiaomi
    '001849': 'Xiaomi', '0C1DAF': 'Xiaomi', '14F65A': 'Xiaomi', '18598B': 'Xiaomi',
    '28A683': 'Xiaomi', '38A4ED': 'Xiaomi', '50B4C6': 'Xiaomi', '58DD47': 'Xiaomi',
    '64E88A': 'Xiaomi', '74F061': 'Xiaomi', '78DBF6': 'Xiaomi', '8CE4B5': 'Xiaomi',
    '98FAE3': 'Xiaomi', 'A4E31E': 'Xiaomi', 'B0E235': 'Xiaomi',
    // Huawei
    '001E10': 'Huawei', '00259E': 'Huawei', '086360': 'Huawei', '1C8E5C': 'Huawei',
    '20F317': 'Huawei', '2CAB25': 'Huawei', '306FF7': 'Huawei', '34A7BA': 'Huawei',
    '447F4B': 'Huawei', '606754': 'Huawei', '68A0F6': 'Huawei', '74FB5A': 'Huawei',
    '84A8E4': 'Huawei', '888E22': 'Huawei', '90E7C4': 'Huawei',
    // LG
    '00A0C8': 'LG', '002483': 'LG', '006037': 'LG', '0C7694': 'LG',
    '10685E': 'LG', '14C913': 'LG', '34C3AC': 'LG', '40B8A0': 'LG', '4C7F2C': 'LG',
    // Motorola
    '000A28': 'Motorola', '003025': 'Motorola', '3C128C': 'Motorola',
    '40F201': 'Motorola', '581FAA': 'Motorola', '7C3548': 'Motorola',
    'A8B8E6': 'Motorola', 'BC5481': 'Motorola', 'C4B9CD': 'Motorola',
    // OnePlus
    '685E1C': 'OnePlus', '7CE9D3': 'OnePlus', '94654A': 'OnePlus',
    'ACCCA9': 'OnePlus', 'B4F1DA': 'OnePlus', 'D8494B': 'OnePlus',
    // ASUS
    '001731': 'ASUS', '001D60': 'ASUS', '002618': 'ASUS', '107B44': 'ASUS',
    '14DAE9': 'ASUS', '1C872C': 'ASUS', '30F9F3': 'ASUS',
    '40167E': 'ASUS', '508002': 'ASUS', '5C514F': 'ASUS', '6C4B90': 'ASUS',
    '84A9C4': 'ASUS', 'AC9E17': 'ASUS', 'BC3400': 'ASUS',
    // TP-Link
    '001422': 'TP-Link', '10BEF5': 'TP-Link', '14CC20': 'TP-Link',
    '18D6C7': 'TP-Link', '1CAAE9': 'TP-Link', '242742': 'TP-Link',
    '2C27D7': 'TP-Link', '30DE4B': 'TP-Link', '40A68D': 'TP-Link',
    '4CE676': 'TP-Link', '500FD5': 'TP-Link', '70A741': 'TP-Link',
    '7C8BCA': 'TP-Link', '84161C': 'TP-Link', '98DAAF': 'TP-Link',
    'C46E1F': 'TP-Link', 'CC32E5': 'TP-Link', 'E8DE27': 'TP-Link',
    // Dell
    '000874': 'Dell', '001185': 'Dell', '001372': 'Dell', '001A4B': 'Dell',
    '001DB3': 'Dell', '001E4F': 'Dell', '18FB7B': 'Dell', '1C40AF': 'Dell',
    '204752': 'Dell', '2C768A': 'Dell', '38CADA': 'Dell', '54BEF7': 'Dell',
    '60D9C7': 'Dell', '6CBA54': 'Dell', '8C04BA': 'Dell', 'F8BC12': 'Dell',
    // HP
    '000D9D': 'HP', '001321': 'HP', '001635': 'HP', '001CC4': 'HP',
    '002170': 'HP', '0024C7': 'HP', '004EA4': 'HP', '0C8112': 'HP',
    '3C52C6': 'HP', '40B034': 'HP', '5CB301': 'HP', '88B111': 'HP',
    '90E6BA': 'HP', 'B8CA3A': 'HP', 'EC3D01': 'HP',
    // Lenovo
    '1A91A7': 'Lenovo', '001A6B': 'Lenovo', '001FB4': 'Lenovo', '044BED': 'Lenovo',
    '10659F': 'Lenovo', '14A3B4': 'Lenovo', '285FC3': 'Lenovo', '2C44FD': 'Lenovo',
    '3CA94B': 'Lenovo', '48BB3A': 'Lenovo', '6CF049': 'Lenovo', '742B0F': 'Lenovo',
    '88706E': 'Lenovo', '98FA9B': 'Lenovo', 'A07734': 'Lenovo',
    // Roku
    '08057F': 'Roku', 'AC3A7A': 'Roku', 'B0A7B9': 'Roku', 'CC6DA0': 'Roku',
    'D4E218': 'Roku', 'DC3A5E': 'Roku', 'F0631A': 'Roku',
    // Realtek
    '00E04C': 'Realtek', '00264B': 'Realtek', '002321': 'Realtek',
    // Broadcom
    '000AF7': 'Broadcom', '00601D': 'Broadcom', 'D86CE9': 'Broadcom',
    // Murata
    '606405': 'Murata', '709EF4': 'Murata', 'C06362': 'Murata', 'F8FFC2': 'Murata',
  };

  String _vendor(String mac) {
    final key = mac.replaceAll(':', '').substring(0, 6).toUpperCase();
    return _oui[key] ?? '';
  }

  String _estimateDistance(int rssi) {
    const txPower = -45;
    const n = 2.7;
    final d = math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
    if (d < 1) return '<1 m';
    if (d > 50) return '>50 m';
    return '~${d.round()}m';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DeviceController>();
    final scanning = ctrl.deviceScanning;
    final stations = ctrl.stations;

    final sorted = [...stations]..sort((a, b) {
        final va = _vendor(a.mac);
        final vb = _vendor(b.mac);
        final aKnown = va.isNotEmpty;
        final bKnown = vb.isNotEmpty;
        if (aKnown && !bKnown) return -1;
        if (!aKnown && bKnown) return 1;
        if (aKnown && bKnown) {
          final vc = va.compareTo(vb);
          if (vc != 0) return vc;
        }
        return a.mac.compareTo(b.mac);
      });

    return Column(
      children: [
        _toolbar(context, ctrl, scanning),
        Expanded(
          child: (stations.isEmpty && !scanning)
              ? _emptyState()
              : (stations.isEmpty && scanning)
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _staTile(context, sorted[i]),
                    ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context, DeviceController ctrl, bool scanning) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: scanning ? null : ctrl.scanDevices,
            icon: scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.radar, size: 18),
            label: Text(scanning ? 'Scanning…' : 'Scan for Devices'),
          ),
          const Spacer(),
          if (ctrl.stations.isNotEmpty)
            Text(
              '${ctrl.stations.length} device${ctrl.stations.length == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.devices_other, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('No devices found — tap Scan'),
        ],
      ),
    );
  }

  Widget _staTile(BuildContext context, StaEntry sta) {
    final vendor = _vendor(sta.mac);
    final known = vendor.isNotEmpty;
    final dist = _estimateDistance(sta.rssi);

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: known
            ? Colors.blue.shade700.withAlpha(40)
            : Colors.grey.shade800,
        child: Icon(
          known ? Icons.devices : Icons.device_unknown,
          size: 18,
          color: known ? Colors.blue.shade300 : Colors.grey,
        ),
      ),
      title: Text(
        known ? vendor : 'Unknown device',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sta.mac,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.grey.shade400,
            ),
          ),
          Text(
            'ch ${sta.channel}  ·  ${sta.rssi} dBm  ·  AP: ${sta.bssid}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            dist,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Icon(Icons.wifi, size: 14, color: Colors.grey),
        ],
      ),
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
            child: AnimatedBuilder(
              animation: _radarCtrl,
              builder: (_, _) => CustomPaint(
                painter: _RadarPainter(
                  sweepAngle: _radarCtrl.value * 2 * math.pi,
                  aps: ctrl.aps,
                  isNuking: isNuking,
                  statusText: statusText,
                  infoText: infoText,
                ),
                child: const SizedBox.expand(),
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
  });

  final double sweepAngle;
  final List<ApEntry> aps;
  final bool isNuking;
  final String statusText;
  final String? infoText;

  static const _bg       = Color(0xFF010D01);
  static const _ring     = Color(0xFF0C3A0C);
  static const _phosphor = Color(0xFF39FF14);
  static const _dimGreen = Color(0xFF1B5C1B);
  static const _targetC  = Color(0xFFFF4800);
  static const _maxM     = 50.0; // outer ring = 50 m

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);
    final r = math.min(cx, cy) - 2;

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

    // AP dots with ping glow
    for (final ap in aps) {
      _paintAp(canvas, ap, center, r);
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
    _paintRangeLabels(canvas, center, r);
    _paintStatus(canvas, center, r);
  }

  void _paintAp(Canvas canvas, ApEntry ap, Offset center, double maxR) {
    final angle = _apAngle(ap);
    final dotR  = _apRadius(ap.rssi, maxR);
    final pos   = Offset(
      center.dx + dotR * math.cos(angle),
      center.dy + dotR * math.sin(angle),
    );

    // age: how many seconds ago the sweep last passed this angle (0..30)
    final age  = _pingAge(angle);
    final glow = math.max(0.0, 1.0 - age / 3.2);

    final col = isNuking ? _targetC : _phosphor;
    final dim = isNuking ? _targetC.withValues(alpha: 0.32) : _dimGreen;

    // Glow halo when freshly swept
    if (glow > 0.04) {
      canvas.drawCircle(
        pos,
        10 * glow,
        Paint()
          ..color = col.withValues(alpha: 0.18 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // Core dot
    canvas.drawCircle(pos, 2.5,
        Paint()..color = glow > 0.04 ? col : dim);

    // SSID label — always present, brighter on ping
    final label =
        ap.ssid.length > 14 ? '${ap.ssid.substring(0, 12)}..' : ap.ssid;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: (glow > 0.04 ? col : dim)
              .withValues(alpha: glow > 0.04 ? 0.6 + 0.4 * glow : 0.38),
          fontSize: 7.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 90);
    tp.paint(canvas, Offset(pos.dx + 5, pos.dy - tp.height / 2));
  }

  void _paintRangeLabels(Canvas canvas, Offset center, double r) {
    const labels = ['12m', '25m', '37m', '50m'];
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

  // Stable angle for an AP derived from the last 3 bytes of its BSSID
  static double _apAngle(ApEntry ap) {
    final b = ap.bssid.split(':');
    final v = int.parse(b[3], radix: 16) << 16 |
              int.parse(b[4], radix: 16) << 8  |
              int.parse(b[5], radix: 16);
    return (v / 16777216.0) * 2 * math.pi;
  }

  // Radial distance on the radar canvas based on RSSI
  static double _apRadius(int rssi, double maxR) {
    // Log-distance: txPower=-45 dBm, n=2.7 → exponent divisor ≈ 27
    final m = math.pow(10.0, (-45.0 - rssi) / 27.0).toDouble();
    return (m.clamp(1.0, _maxM) / _maxM) * maxR;
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
