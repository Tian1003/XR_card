// lib/services/bluetooth_service.dart
// BLE 掃描 / 連線 / 中斷（⚠️ 只包含 BluetoothService；絕對不要放 ParsedAdv / NearbyPresence）

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

class BluetoothService {
  BluetoothService._();
  static final BluetoothService I = BluetoothService._();

  StreamSubscription<List<fbp.ScanResult>>? _scanResultsSub;
  StreamSubscription<fbp.BluetoothAdapterState>? _adapterSub;

  final ValueNotifier<fbp.BluetoothAdapterState> adapterState =
      ValueNotifier(fbp.BluetoothAdapterState.unknown);
  final ValueNotifier<bool> isScanning = ValueNotifier(false);
  final ValueNotifier<List<fbp.ScanResult>> results = ValueNotifier(const []);

  fbp.BluetoothDevice? _connected;

  Future<void> init() async {
    await _adapterSub?.cancel();
    _adapterSub = fbp.FlutterBluePlus.adapterState.listen((s) {
      adapterState.value = s;
    });
  }

  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final req = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    return req.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    if (isScanning.value) return;

    results.value = const [];
    isScanning.value = true;

    await fbp.FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: true,
    );

    await _scanResultsSub?.cancel();
    _scanResultsSub = fbp.FlutterBluePlus.scanResults.listen((list) {
      final map = <String, fbp.ScanResult>{};
      for (final r in list) {
        final id = r.device.remoteId.str;
        if (!map.containsKey(id) || r.rssi > (map[id]?.rssi ?? -999)) {
          map[id] = r;
        }
      }
      results.value = map.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
    });

    fbp.FlutterBluePlus.isScanning.listen((s) {
      isScanning.value = s;
    });
  }

  Future<void> stopScan() async {
    if (isScanning.value) {
      await fbp.FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    isScanning.value = false;
  }

  Future<void> connect(
    fbp.BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await stopScan();
    try {
      await _connected?.disconnect();
    } catch (_) {}
    await device.connect(timeout: timeout, autoConnect: false);
    _connected = device;
  }

  Future<void> disconnect() async {
    try {
      await _connected?.disconnect();
    } catch (_) {}
    _connected = null;
  }

  Future<bool> waitUntilPoweredOn({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (adapterState.value == fbp.BluetoothAdapterState.on) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return adapterState.value == fbp.BluetoothAdapterState.on;
  }

  void dispose() {
    _scanResultsSub?.cancel();
    _adapterSub?.cancel();
  }
}
