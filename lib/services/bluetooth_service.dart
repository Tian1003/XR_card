// lib/services/bluetooth_service.dart
// 簡易 BLE 封裝：掃描 / 連線 / 中斷

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// 可選：權限
import 'package:permission_handler/permission_handler.dart';

class BluetoothService {
  BluetoothService._();
  static final BluetoothService I = BluetoothService._();

  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  final ValueNotifier<BluetoothAdapterState> adapterState =
      ValueNotifier(BluetoothAdapterState.unknown);
  final ValueNotifier<bool> isScanning = ValueNotifier(false);
  final ValueNotifier<List<ScanResult>> results = ValueNotifier(const []);

  BluetoothDevice? _connected;

  Future<void> init() async {
    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      adapterState.value = s;
    });
  }

  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true; // iOS 由系統彈窗

    // Android：請求 BLE 與定位權限（不同版本會自動對應）
    final req = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final ok = req.values.every((s) => s.isGranted || s.isLimited);
    return ok;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 6)}) async {
    if (isScanning.value) return;
    results.value = const [];

    isScanning.value = true;
    await FlutterBluePlus.startScan(timeout: timeout, androidUsesFineLocation: true);

    _scanResultsSub?.cancel();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((list) {
      // 去重（以 device.remoteId.str 當 key）
      final map = <String, ScanResult>{};
      for (final r in list) {
        final id = r.device.remoteId.str;
        // 僅保留名稱或 RSSI 較佳者
        if (!map.containsKey(id) || r.rssi > (map[id]?.rssi ?? -999)) {
          map[id] = r;
        }
      }
      results.value = map.values.toList()
        ..sort((a, b) => (b.rssi).compareTo(a.rssi));
    });

    // FlutterBluePlus 自帶 timeout，這裡用 isScanning 反映狀態
    FlutterBluePlus.isScanning.listen((s) {
      isScanning.value = s;
    });
  }

  Future<void> stopScan() async {
    if (isScanning.value) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    isScanning.value = false;
  }

  Future<void> connect(BluetoothDevice device, {Duration timeout = const Duration(seconds: 12)}) async {
    // 連線前先停掃描，避免干擾
    await stopScan();

    // 若已有連線，先斷開
    try { await _connected?.disconnect(); } catch (_) {}

    await device.connect(timeout: timeout, autoConnect: false);
    _connected = device;
  }

  Future<void> disconnect() async {
    try { await _connected?.disconnect(); } catch (_) {}
    _connected = null;
  }

  void dispose() {
    _scanResultsSub?.cancel();
    _adapterSub?.cancel();
  }
}