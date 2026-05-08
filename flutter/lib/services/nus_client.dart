// Nordic UART Service (NUS) BLE client.
//
// Pairs with the firmware's transport_ble.c GATT layout:
//   Service: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
//   RX char: 6E400002-…   (write / write-no-rsp — host → device)
//   TX char: 6E400003-…   (notify              — device → host)
//
// Public surface:
//   - scan()              streams discovered peripherals advertising the NUS
//   - connect(device)     hooks up TX/RX, returns Stream<String> of incoming
//                         text and an `Sink<String> sink` to write commands
//   - disconnect()        tear-down

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class NusUuids {
  static final Guid service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid rx      = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid tx      = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');
}

class NusConnection {
  NusConnection._({
    required this.device,
    required BluetoothCharacteristic rx,
    required this.incoming,
    required this.disconnect,
  }) : _rx = rx;

  final BluetoothDevice device;
  final BluetoothCharacteristic _rx;
  final Stream<String> incoming;
  final Future<void> Function() disconnect;

  /// Sends `text` to the device's RX characteristic. Adds a trailing newline
  /// if missing (the firmware CLI is line-buffered).
  Future<void> send(String text) async {
    if (!text.endsWith('\n')) text = '$text\n';
    final bytes = utf8.encode(text);
    // Try write-without-response first (lower latency for short commands);
    // fall back to write-with-response if the characteristic doesn't accept it.
    final wnrSupported = _rx.properties.writeWithoutResponse;
    await _rx.write(bytes, withoutResponse: wnrSupported);
  }
}

class NusClient {
  StreamSubscription<List<ScanResult>>? _scanSub;

  /// Streams scan results filtered to peripherals advertising the NUS service
  /// or named like our firmware. Caller is expected to call [stopScan] when
  /// done. Safe to call multiple times.
  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)}) {
    final controller = StreamController<List<ScanResult>>.broadcast();
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where(_looksLikeDevice).toList();
      if (!controller.isClosed) controller.add(filtered);
    });
    // On Android, filter by service UUID for efficiency. On Linux/macOS/
    // Windows, BlueZ and CoreBluetooth only match UUIDs in the primary
    // advertisement — our NUS UUID is in the scan response to stay within
    // the 31-byte limit, so the filter would silently drop the device.
    if (Platform.isAndroid) {
      FlutterBluePlus.startScan(
        timeout: timeout,
        withServices: [NusUuids.service],
        androidScanMode: AndroidScanMode.lowLatency,
      ).catchError((_) => FlutterBluePlus.startScan(timeout: timeout));
    } else {
      FlutterBluePlus.startScan(timeout: timeout);
    }
    controller.onCancel = () async {
      await stopScan();
    };
    return controller.stream;
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  bool _looksLikeDevice(ScanResult r) {
    final uuids = r.advertisementData.serviceUuids.map((u) => u.str.toLowerCase()).toList();
    if (uuids.contains(NusUuids.service.str.toLowerCase())) return true;
    final name = (r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : r.device.platformName);
    return name.toLowerCase().contains('deauther') ||
        name.toLowerCase().contains('esp32c5');
  }

  /// Connect, discover services, subscribe to TX notifications, return a
  /// [NusConnection] that exposes the bidirectional channel.
  Future<NusConnection> connect(BluetoothDevice device) async {
    await stopScan();
    await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);

    // Try to bump MTU — bigger notifications mean fewer per-message
    // fragments. The device requested 247 in the firmware. Some platforms
    // ignore this; that's fine.
    try {
      await device.requestMtu(247);
    } catch (_) {/* not supported on iOS / desktop */}

    final services = await device.discoverServices();
    final svc = services.firstWhere(
      (s) => s.uuid == NusUuids.service,
      orElse: () => throw StateError('NUS service not found on this device'),
    );

    final rx = svc.characteristics.firstWhere(
      (c) => c.uuid == NusUuids.rx,
      orElse: () => throw StateError('NUS RX characteristic missing'),
    );
    final tx = svc.characteristics.firstWhere(
      (c) => c.uuid == NusUuids.tx,
      orElse: () => throw StateError('NUS TX characteristic missing'),
    );

    await tx.setNotifyValue(true);

    // Decode incoming bytes as UTF-8 text. The firmware sends raw log lines.
    final incoming = tx.lastValueStream.map((bytes) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    });

    Future<void> disconnect() async {
      try { await tx.setNotifyValue(false); } catch (_) {}
      try { await device.disconnect(); } catch (_) {}
    }

    return NusConnection._(
      device: device,
      rx: rx,
      incoming: incoming,
      disconnect: disconnect,
    );
  }
}
