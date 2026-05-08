import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/device_controller.dart';
import '../services/nus_client.dart';
import 'device_screen.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    _maybeStartScan();
  }

  @override
  void dispose() {
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
      try { await FlutterBluePlus.turnOn(); return true; } catch (_) {}
    }
    if (mounted) setState(() => _error = 'Bluetooth is off — enable it and retry.');
    return false;
  }

  void _startScan() {
    setState(() {
      _error = null;
      _results = [];
    });
    _resultsSub?.cancel();
    _resultsSub = _client.scan().listen((rs) {
      if (mounted) setState(() => _results = rs);
    }, onError: (e) {
      if (mounted) setState(() => _error = 'scan error: $e');
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _error = null);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final conn = await _client.connect(device);
      final controller = DeviceController(conn);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss spinner
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DeviceScreen(controller: controller),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() => _error = '$e');
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
                _client.stopScan();
              } else {
                _maybeStartScan();
              }
            },
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
                      _scanning ? 'Scanning…' : 'No devices yet — tap refresh',
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
