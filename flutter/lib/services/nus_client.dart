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
//                         text and a `send()` to write commands
//   - NusConnection.disconnect()       graceful tear-down
//   - NusConnection.disconnected       Future that completes when peer drops

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
    required this.disconnected,
    required Future<void> Function() doDisconnect,
  })  : _rx = rx,
        _doDisconnect = doDisconnect;

  final BluetoothDevice device;
  final BluetoothCharacteristic _rx;

  /// Stream of UTF-8 decoded notifications from the TX characteristic.
  /// Only emits NEW notifications (not the cached `lastValueStream`), so
  /// a fresh connection never sees stale data from a previous session.
  final Stream<String> incoming;

  /// Resolves when the BLE link drops for any reason — graceful disconnect,
  /// peer drop, RF loss. Use this to drive UI state transitions instead of
  /// polling `device.isConnected`.
  final Future<void> disconnected;

  final Future<void> Function() _doDisconnect;
  bool _disconnectCalled = false;

  /// Sends `text` to the device's RX characteristic. Adds a trailing newline
  /// if missing (the firmware CLI is line-buffered). Silently no-ops if the
  /// device has dropped — callers don't need to wrap each call.
  Future<void> send(String text) async {
    if (!device.isConnected) return;
    if (!text.endsWith('\n')) text = '$text\n';
    final bytes = utf8.encode(text);
    final wnrSupported = _rx.properties.writeWithoutResponse;
    try {
      await _rx.write(bytes, withoutResponse: wnrSupported);
    } on FlutterBluePlusException catch (_) {
      // Device disconnected mid-write — disconnected future will fire shortly.
    }
  }

  Future<void> disconnect() async {
    if (_disconnectCalled) return;
    _disconnectCalled = true;
    await _doDisconnect();
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
    try { await FlutterBluePlus.stopScan(); } catch (_) {}
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
  /// [NusConnection] exposing the bidirectional channel.
  ///
  /// Safe to call against the same `device` repeatedly — any prior link is
  /// torn down and the GATT cache invalidated (Android) before re-opening.
  Future<NusConnection> connect(BluetoothDevice device) async {
    await stopScan();

    // If the platform still thinks we're connected from a prior session,
    // tear it down first. flutter_blue_plus will otherwise return immediately
    // from connect() with a stale handle and service discovery will fail.
    if (device.isConnected) {
      try { await device.disconnect(); } catch (_) {}
      await _waitForState(device, BluetoothConnectionState.disconnected,
          const Duration(seconds: 3));
    }

    // Android caches GATT services per-device. If the firmware was rebuilt
    // (handles renumbered) the cache is stale and discoverServices returns
    // garbage. Force-clear before connecting.
    if (Platform.isAndroid) {
      try { await device.clearGattCache(); } catch (_) {}
    }

    await device.connect(timeout: const Duration(seconds: 12), autoConnect: false);
    await _waitForState(device, BluetoothConnectionState.connected,
        const Duration(seconds: 12));

    // Bigger MTU = fewer notification fragments. The firmware requested 247.
    // Some platforms (iOS / desktop) ignore this — that's fine.
    try {
      await device.requestMtu(247);
    } catch (_) {}

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

    // CRITICAL: use onValueReceived (new notifications only), NOT
    // lastValueStream (which replays the cached last value at subscribe time
    // and would inject a stale chunk from the previous session into the
    // parser on every reconnect).
    final incoming = tx.onValueReceived.map((bytes) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    });

    // Resolve `disconnected` when the device transitions to disconnected,
    // regardless of who initiated it.
    final disconnectedCompleter = Completer<void>();
    late StreamSubscription<BluetoothConnectionState> stateSub;
    stateSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected
          && !disconnectedCompleter.isCompleted) {
        disconnectedCompleter.complete();
        stateSub.cancel();
      }
    });

    Future<void> doDisconnect() async {
      try { await tx.setNotifyValue(false); } catch (_) {}
      try { await device.disconnect(); } catch (_) {}
      // Wait for the platform to confirm the disconnect so the next
      // connect() attempt starts from a clean slate.
      try {
        await _waitForState(device, BluetoothConnectionState.disconnected,
            const Duration(seconds: 3));
      } catch (_) {}
      try { await stateSub.cancel(); } catch (_) {}
    }

    return NusConnection._(
      device: device,
      rx: rx,
      incoming: incoming,
      disconnected: disconnectedCompleter.future,
      doDisconnect: doDisconnect,
    );
  }

  Future<void> _waitForState(
    BluetoothDevice device,
    BluetoothConnectionState target,
    Duration timeout,
  ) async {
    if (await device.connectionState.first == target) return;
    await device.connectionState
        .firstWhere((s) => s == target)
        .timeout(timeout);
  }
}
