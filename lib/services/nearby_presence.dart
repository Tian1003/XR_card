// lib/services/nearby_presence.dart
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' as io;

import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../data/supabase_services.dart';

//定義 uuid （本軟體的 id）
const int _kMagic = 0xA1B2C3D4;


class ParsedAdv {
  final int userId;
  final Uint8List token;
  ParsedAdv(this.userId, this.token);
}


class NearbyPresence {
  NearbyPresence._();
  static final NearbyPresence I = NearbyPresence._();

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  bool _advertising = false;
  Uint8List? _token;

  bool get isAdvertising => _advertising;
  Uint8List get currentToken => _token ?? Uint8List(0);

  // ---------- helpers: bytes <-> uuid ----------
  static String _bytesToUuid(Uint8List b) {
    // 16 bytes -> xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
           '${hex.substring(8, 12)}-'
           '${hex.substring(12, 16)}-'
           '${hex.substring(16, 20)}-'
           '${hex.substring(20)}';
  }

  static Uint8List? _uuidToBytes(String s) {
    final h = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (h.length != 32) return null;
    final out = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _buildDynamicServiceUuid(int userId, Uint8List token) {
    final b = Uint8List(16);
    final bd = ByteData.view(b.buffer);
    // 用 Big Endian，解析時一致即可
    bd.setUint32(0, _kMagic, Endian.big);
    bd.setUint32(4, userId, Endian.big);
    for (int i = 0; i < 8; i++) {
      b[8 + i] = token[i];
    }
    return _bytesToUuid(b);
  }

  Future<void> start() async {
    if (_advertising) return;

    _token ??= _genToken();
    final uid = SupabaseService.currentUserId;

    // ➜ 直接把身分塞進「Service UUID 本身」
    final dynamicUuid = _buildDynamicServiceUuid(uid, _token!);

    final data = AdvertiseData(
      includeDeviceName: false,
      serviceUuid: dynamicUuid,
      // 不再依賴 manufacturerData（iOS 常常丟失）
      // manufacturerId / manufacturerData 省略
    );

    final settings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeLowLatency,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
      connectable: true,   // iOS/Android 都設 true，穩定
      timeout: 0,
    );

    await _peripheral.start(advertiseData: data, advertiseSettings: settings);
    _advertising = true;
  }

  Future<void> stop() async {
    if (!_advertising) return;
    await _peripheral.stop();
    _advertising = false;
  }

  Future<void> restart() async {
    try { await _peripheral.stop(); } catch (_) {}
    _advertising = false;
    await start();
  }

  /// 解析：從 service UUID 把 [MAGIC|userId|token] 拉出來
  static ParsedAdv? parseAdvAll(fbp.AdvertisementData adv) {
    for (final g in adv.serviceUuids) {
      final bytes = _uuidToBytes(g.str);
      if (bytes == null) continue;
      final bd = ByteData.view(bytes.buffer);
      final magic = bd.getUint32(0, Endian.big);
      if (magic != _kMagic) continue;

      final uid = bd.getUint32(4, Endian.big);
      final token = Uint8List.fromList(bytes.sublist(8, 16));
      return ParsedAdv(uid, token);
    }
    // 沒看到我們的 magic → 非我方廣告
    return null;
  }

  Uint8List _genToken() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(8, (_) => r.nextInt(256)));
  }
}
