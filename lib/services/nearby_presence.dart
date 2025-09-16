// lib/services/nearby_presence.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NearbyPresence {
  NearbyPresence._();
  static final NearbyPresence I = NearbyPresence._();

  /// 上線前請換成你們的正式 Manufacturer ID
  static const int manufacturerId = 0xFFFF;

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  bool _advertising = false;
  Uint8List? _token;       // 8 bytes session token
  String? _userId;         // Supabase auth user id（UUID 字串）

  bool get isAdvertising => _advertising;
  Uint8List get currentToken => _token ?? Uint8List(0);
  String get tokenHex => _token == null
      ? ''
      : _token!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  String get userId => _userId ?? '';

  /// 開始前景廣播：[16B userId][8B token] 放在 Manufacturer Data
  Future<void> start() async {
    if (_advertising) return;

    // 取目前登入者的 userId；若尚未登入，給一個臨時 UUID（僅為避免 null）
    _userId = Supabase.instance.client.auth.currentUser?.id ?? _randomUuidV4();
    _token ??= _generateToken();

    // 組 24 bytes：0..15 = userId(16B), 16..23 = token(8B)
    final md = Uint8List(24)
      ..setRange(0, 16, _uuidToBytes(_userId!))
      ..setRange(16, 24, _token!);

    final data = AdvertiseData(
      includeDeviceName: false,
      manufacturerId: manufacturerId,
      manufacturerData: md,                // 這裡是我們組好的 24 bytes
      serviceUuid: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
      includePowerLevel: true,             // ← 改這行（取代 includeTxPowerLevel）
    );


    final settings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeLowLatency,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
      connectable: false,
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

  // —— 工具們 —— //

  /// 將 UUID 字串（含 -）轉為 16 bytes
  static Uint8List _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    final out = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// 將 16 bytes 轉回 UUID 字串
  static String _bytesToUuid(Uint8List b) {
    final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
           '${hex.substring(8, 12)}-'
           '${hex.substring(12, 16)}-'
           '${hex.substring(16, 20)}-'
           '${hex.substring(20)}';
  }

  /// 從 Manufacturer Data 解析出 userId 與 token（若不是本 App 或長度不夠回 null）
  static ParsedAdv? parseManufacturerData(Map<int, List<int>> md) {
    final raw = md[manufacturerId];
    if (raw == null || raw.length < 24) return null;
    final bytes = Uint8List.fromList(raw);
    final userIdBytes = bytes.sublist(0, 16);
    final tokenBytes = bytes.sublist(16, 24);
    final uid = _bytesToUuid(userIdBytes);
    final tokHex = tokenBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return ParsedAdv(userId: uid, tokenHex: tokHex);
  }

  static Uint8List _generateToken() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(8, (_) => r.nextInt(256)));
  }

  /// 產一個簡單的 v4 UUID（只在未登入時避免 null 用）
  static String _randomUuidV4() {
    final r = Random.secure();
    Uint8List bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) bytes[i] = r.nextInt(256);
    // RFC 4122 v4 variant bits
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-'
           '${hex.substring(16,20)}-${hex.substring(20)}';
  }
}

/// 解析結果：掃描端可直接拿到對方 userId 與 tokenHex
class ParsedAdv {
  final String userId;
  final String tokenHex;
  ParsedAdv({required this.userId, required this.tokenHex});
}
