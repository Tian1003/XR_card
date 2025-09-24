import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'package:my_app/data/supabase_services.dart' show SupabaseService;
import 'package:my_app/features/exchange/card_exchange_page.dart';


import '../../services/bluetooth_service.dart' as bt;
import '../../services/nearby_presence.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;


class BluetoothConnectingPage extends StatefulWidget {
  const BluetoothConnectingPage({super.key, this.onCancel});
  final VoidCallback? onCancel;

  @override
  State<BluetoothConnectingPage> createState() => _BluetoothConnectingPageState();
}

class _BluetoothConnectingPageState extends State<BluetoothConnectingPage>
    with SingleTickerProviderStateMixin {
  // 動畫（波紋）
  late final AnimationController _anim;
  // 目前鎖定的候選（最近且可解析）
  _Candidate? _current;
  // 連續穩定鎖定的起點時間
  DateTime? _since;
  // 冷卻避免重複跳交換（例如剛剛交換完又偵測到）
  final Map<int, DateTime> _cooldown = {}; // userId -> lastHandledAt
  final Duration _cooldownDur = const Duration(seconds: 20);
  // 至少穩定 5 秒才進入交換頁
  final Duration _hold = const Duration(seconds: 5);

  // 已是好友（accepted）的 userId 集合
  final Set<int> _friends = {};
  // 自己的 userId
  late final int _me;

  // 綁定掃描結果的監聽
  void _onScanUpdated() {
    if (!mounted) return;

    // 取出可解析且不是自己、不是好友、沒在冷卻中的候選
    final list = bt.BluetoothService.I.results.value;
    _Candidate? best;

    for (final r in list) {
      final parsed = NearbyPresence.parseAdvAll(r.advertisementData);
      if (parsed == null || parsed.userId < 0) continue;
      final peerId = parsed.userId;

      if (peerId == _me) continue;            // 排除自己
      if (_friends.contains(peerId)) continue; // 排除已是好友
      final cd = _cooldown[peerId];
      if (cd != null && DateTime.now().difference(cd) < _cooldownDur) {
        continue;
      }

      // 取 RSSI 最強者為 best
      if (best == null || r.rssi > best.result.rssi) {
        best = _Candidate(result: r, userId: peerId);
      }
    }

    // 沒人就清空鎖定狀態，讓波紋顯示「搜尋中…」
    if (best == null) {
      if (_current != null) {
        _current = null;
        _since = null;
        if (mounted) setState(() {});
      }
      return;
    }

    // 若人不同則重設鎖定起點；若同一個就累計時間
    final changed = _current?.userId != best.userId ||
        _current?.result.device.remoteId.str != best.result.device.remoteId.str;
    _current = best;
    if (changed || _since == null) {
      _since = DateTime.now();
      if (mounted) setState(() {}); // 更新 UI 顯示「已找到對象」
      return;
    }

    // 已鎖定超過 _hold → 進入交換
    if (DateTime.now().difference(_since!) >= _hold) {
      final peerId = _current!.userId;
      // 冷卻與護欄
      if (_cooldown[peerId] == null ||
          DateTime.now().difference(_cooldown[peerId]!) >= _cooldownDur) {
        _cooldown[peerId] = DateTime.now();
        _goExchange(peerId);
      }
    }
  }

  Future<void> _goExchange(int peerUserId) async {
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CardExchangePage(peerUserId: peerUserId),
      ),
    );
  }


  @override
  void initState() {
    super.initState();

    _me = SupabaseService.currentUserId;

    // 波紋動畫
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // iOS 偶發殘留，先重啟廣播
    NearbyPresence.I.restart();

    // 啟動掃描與載入好友名單
    () async {
      await bt.BluetoothService.I.init();
      await bt.BluetoothService.I.ensurePermissions();
      await bt.BluetoothService.I.waitUntilPoweredOn();

      // 先載入已接受的好友，避免在偵測頁一直撞到熟人
      try {
        final svc = SupabaseService(Supabase.instance.client);
        final accepted = await svc.fetchAcceptedContacts(_me);
        final mine = <int>{};
        for (final rel in accepted) {
          final a = rel.requesterId;
          final b = rel.friendId;
          final peer = (a == _me) ? b : a;
          mine.add(peer);
        }
        _friends
          ..clear()
          ..addAll(mine);
      } catch (_) {
        // 靜默失敗也沒關係，頂多不過濾
      }

      bt.BluetoothService.I.startScan();

      // 綁定掃描結果
      bt.BluetoothService.I.results.addListener(_onScanUpdated);

      // 若 2 秒內完全沒有可解析者，重啟一次廣播試試
      Future.delayed(const Duration(seconds: 2), () {
        final any = bt.BluetoothService.I.results.value.any(
          (r) => NearbyPresence.parseAdvAll(r.advertisementData) != null,
        );
        if (!any) NearbyPresence.I.restart();
      });
    }();
  }

  @override
  void dispose() {
    bt.BluetoothService.I.results.removeListener(_onScanUpdated);
    bt.BluetoothService.I.stopScan();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lockedUserId = _current?.userId;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // 跟 profile_page 同系的底色
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            widget.onCancel?.call();
            Navigator.of(context).maybePop();
          },
        ),
        title: const Text('搜尋附近使用者'),
      ),
      body: Stack(
        children: [
          // 波紋
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                return CustomPaint(
                  painter: _RipplePainter(progress: _anim.value),
                );
              },
            ),
          ),
          // 中央圖標＋文案
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bluetooth_searching, size: 72),
                const SizedBox(height: 16),
                Text(
                  lockedUserId == null
                      ? '正在尋找附近裝置…'
                      : '已鎖定對象（userId $lockedUserId）\n保持靠近以開始交換',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  '需要偵測穩定約 5 秒，雙方停留在這個畫面',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Candidate {
  final fbp.ScanResult result;
  final int userId;
  _Candidate({required this.result, required this.userId});
}

// 單畫面簡易波紋
class _RipplePainter extends CustomPainter {
  final double progress; // 0..1
  _RipplePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = (size.shortestSide * 0.45);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 畫 3 道波紋，彼此 phase 差 1/3
    for (int i = 0; i < 3; i++) {
      final p = (progress + i / 3) % 1.0;
      final r = 16.0 + maxR * p;
      paint.color = Colors.black.withOpacity((1 - p).clamp(0.0, 1.0));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
