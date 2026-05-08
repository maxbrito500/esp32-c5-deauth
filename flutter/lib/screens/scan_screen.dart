import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../services/api_server.dart';
import '../services/device_controller.dart';
import '../services/nus_client.dart';
import 'device_screen.dart';
import 'settings_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final NusClient _client = NusClient();
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<bool>? _scanningSub;
  List<ScanResult> _results = [];
  bool _scanning = false;
  bool _connecting = false;
  Timer? _rescanTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (!mounted) return;
      final wasScanning = _scanning;
      setState(() => _scanning = s);
      // When a scan cycle ends naturally, schedule the next one in 5 seconds.
      if (wasScanning && !s && !_connecting) {
        _rescanTimer?.cancel();
        _rescanTimer = Timer(const Duration(seconds: 5), () {
          if (mounted && !_connecting) _maybeStartScan();
        });
      }
    });
    _maybeStartScan();
  }

  @override
  void dispose() {
    _rescanTimer?.cancel();
    _resultsSub?.cancel();
    _scanningSub?.cancel();
    _client.stopScan();
    super.dispose();
  }

  Future<void> _maybeStartScan() async {
    if (!await _ensurePermissions()) return;
    if (!await _ensureAdapterOn()) return;
    _startScan();
  }

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final ok = statuses.values.every((s) => s.isGranted || s.isLimited);
    if (!ok && mounted) {
      setState(() => _error = 'Bluetooth/location permissions denied.');
    }
    return ok;
  }

  Future<bool> _ensureAdapterOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) return true;
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
        return true;
      } catch (_) {}
    }
    if (mounted) setState(() => _error = 'Bluetooth is off — enable it and retry.');
    return false;
  }

  void _startScan() {
    _rescanTimer?.cancel();
    setState(() {
      _error = null;
      _results = [];
    });
    _resultsSub?.cancel();
    _resultsSub = _client.scan().listen((rs) {
      if (!mounted) return;
      setState(() => _results = rs);
      // Auto-connect when exactly one device is visible.
      if (rs.length == 1 && !_connecting) _connect(rs.first.device);
    }, onError: (e) {
      if (mounted) setState(() => _error = 'scan error: $e');
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_connecting) return;
    _rescanTimer?.cancel();
    setState(() {
      _error = null;
      _connecting = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final conn = await _client.connect(device);
      final controller = DeviceController(conn);
      if (!mounted) return;
      final api = context.read<ApiServer>();
      api.attach(controller);
      Navigator.of(context).pop(); // dismiss spinner
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DeviceScreen(controller: controller)),
      );
      api.detach();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
        _maybeStartScan(); // resume scanning after disconnect or error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32-C5 Deauther'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.stop : Icons.refresh),
            tooltip: _scanning ? 'Stop scan' : 'Scan',
            onPressed: () {
              if (_scanning) {
                _rescanTimer?.cancel();
                _client.stopScan();
              } else {
                _maybeStartScan();
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? 'Scanning…' : 'No devices found',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _resultTile(_results[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _resultTile(ScanResult r) {
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : (r.device.platformName.isNotEmpty ? r.device.platformName : '(unnamed)');
    return ListTile(
      leading: const Icon(Icons.bluetooth),
      title: Text(name),
      subtitle: Text('${r.device.remoteId}\n${r.rssi} dBm'),
      isThreeLine: true,
      onTap: () => _connect(r.device),
    );
  }
}
