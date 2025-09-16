// lib/features/connect/bluetooth_connecting_page.dart
import 'dart:async';
import 'dart:ui' show FontFeature, lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import '../../services/bluetooth_service.dart' as ble;
import '../../services/nearby_presence.dart';
import '../../services/relationship_service.dart';

class BluetoothConnectingPage extends StatefulWidget {
  final VoidCallback onCancel;
  const BluetoothConnectingPage({super.key, required this.onCancel});

  @override
  State<BluetoothConnectingPage> createState() => _BluetoothConnectingPageState();
}

class _BluetoothConnectingPageState extends State<BluetoothConnectingPage>
    with TickerProviderStateMixin {
  late final AnimationController _wave;
  late final Animation<double> _anim;

  VoidCallback? _adapterListener;

  bool _connecting = false;
  fbp.BluetoothDevice? _connectingDevice;
  fbp.BluetoothDevice? _connectedDevice;

  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _anim = CurvedAnimation(parent: _wave, curve: Curves.easeInOut);

    ble.BluetoothService.I.init();
    _adapterListener = () {
      if (mounted) setState(() {});
    };
    ble.BluetoothService.I.adapterState.addListener(_adapterListener!);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 進場開始廣播 userId + token（只在這個頁面才廣播）
      await NearbyPresence.I.start();

      final ok = await ble.BluetoothService.I.ensurePermissions();

      // 訂閱入站 pending：有人把我當 friend_id 插入一筆 pending
      await RelationshipService.I.subscribeForIncomingPending(
        (row) async {
          final requesterId = row['requester_id'] as String;
          return await _ask('有人想與你交換名片，接受嗎？\n(requester: ${requesterId.substring(0, 8)}…)');
        },
        (acceptedRow) {
          final other = acceptedRow['requester_id'] as String;
          _showSnack('已與 ${other.substring(0, 8)}… 建立關係');
          // TODO: 在此導頁到 ExchangePage（若需要）
        },
      );

      if (!ok && mounted) {
        _showSnack('未授權藍牙/定位，可能無法掃描');
      }
      await _scan();
    });
  }

  Future<void> _scan() async {
    try {
      await ble.BluetoothService.I.startScan();
    } catch (e) {
      _showSnack('開始掃描失敗：$e');
    }
  }

  Future<void> _stopScan() => ble.BluetoothService.I.stopScan();

  /// 解析本 App 的廣播（有 [16B userId][8B token]）
  ParsedAdv? _parsed(fbp.AdvertisementData adv) {
    return NearbyPresence.parseManufacturerData(adv.manufacturerData);
  }

  Future<void> _connect(fbp.ScanResult r) async {
    // 只對本 App 裝置（有 userId+token）進行下一步
    final parsed = _parsed(r.advertisementData);
    if (parsed == null) {
      _showSnack('對方不是本 App 或未在配對頁');
      return;
    }
    final otherUserId = parsed.userId;

    // 詢問本人是否要發起
    final ok = await _ask('與「${_prettyName(r)}」交換名片？');
    if (!ok) return;

    // 1) 建立 pending（我 -> 對方）
    await RelationshipService.I.createPending(otherUserId: otherUserId);

    // 2) 監看我發出去的那筆何時被對方接受
    await RelationshipService.I.watchMyOutgoing(
      otherUserId: otherUserId,
      onAccepted: (row) {
        _showSnack('對方已接受！');
        // TODO: 在此導頁到 ExchangePage（若需要）
      },
    );

    // 視覺上的 BLE 連線流程（保留原體驗，不影響上面 Realtime 協商）
    HapticFeedback.mediumImpact();
    setState(() {
      _connecting = true;
      _connectingDevice = r.device;
    });
    try {
      await ble.BluetoothService.I.connect(r.device);
      setState(() {
        _connectedDevice = r.device;
        _showSuccess = true;
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _showSuccess = false);
      });
      _showSnack('已連線到 ${_prettyName(r)}（對方 userId: ${otherUserId.substring(0, 8)}…）');
    } catch (e) {
      _showSnack('連線失敗：$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _prettyName(fbp.ScanResult r) {
    final d = r.device;
    return d.platformName.isNotEmpty
        ? d.platformName
        : (r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : d.remoteId.str);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _ask(String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('交換名片'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('接受'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  void dispose() {
    // 離開頁面就關掉廣播與訂閱
    NearbyPresence.I.stop();
    RelationshipService.I.unsubscribeAll();

    if (_adapterListener != null) {
      ble.BluetoothService.I.adapterState.removeListener(_adapterListener!);
    }
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5A5A5A),
      body: Stack(
        children: [
          Positioned.fill(child: _RippleBackground(animation: _anim)),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(),
                const SizedBox(height: 12),
                _header(),
                const SizedBox(height: 12),
                Expanded(child: _deviceList()),
                const SizedBox(height: 16),
                _bottomButtons(),
                const SizedBox(height: 16),
              ],
            ),
          ),
          if (_connecting) _connectingOverlay(),
          if (_showSuccess) _successOverlay(), // 覆蓋層不攔截點擊
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48),
          const Text(
            '連線裝置',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          GestureDetector(
            onTap: () async {
              await _stopScan();
              await ble.BluetoothService.I.disconnect();
              widget.onCancel();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('取消', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_searching, color: Colors.white),
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: ble.BluetoothService.I.isScanning,
            builder: (_, scanning, __) {
              return Text(
                scanning ? '正在搜尋鄰近裝置…' : '掃描已停止，可重新整理',
                style: const TextStyle(color: Colors.white70),
              );
            },
          ),
          const Spacer(),
          IconButton(
            onPressed: () async {
              HapticFeedback.selectionClick();
              await ble.BluetoothService.I.stopScan();
              await _scan();
            },
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: '重新掃描',
          ),
        ],
      ),
    );
  }

  Widget _deviceList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.white.withOpacity(0.08),
          child: ValueListenableBuilder<List<fbp.ScanResult>>(
            valueListenable: ble.BluetoothService.I.results,
            builder: (_, list, __) {
              // 僅顯示廣播了本 App 標記的裝置
              final filtered = list.where((r) => _parsed(r.advertisementData) != null).toList();
              if (filtered.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text('附近沒有正在配對頁的本 App 裝置', style: TextStyle(color: Colors.white70)),
                  ),
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    Divider(color: Colors.white.withOpacity(0.08), height: 1),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  final name = _prettyName(r);
                  final id = r.device.remoteId.str;
                  final rssi = r.rssi;
                  final parsed = _parsed(r.advertisementData)!; // 保證非空
                  return ListTile(
                    onTap: () => _connect(r),
                    leading: const Icon(Icons.bluetooth, color: Colors.white),
                    title: Text(name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'id:$id\nuid:${parsed.userId.substring(0, 8)}…',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: Text(
                      '$rssi dBm',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _bottomButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.lightImpact();
                await ble.BluetoothService.I.stopScan();
                await _scan();
              },
              icon: const Icon(Icons.search),
              label: const Text('重新掃描'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _connectedDevice == null
                  ? null
                  : () {
                      Navigator.of(context).pop(_connectedDevice);
                    },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('完成'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectingOverlay() {
    final dev = _connectingDevice;
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                dev == null
                    ? '正在連線…'
                    : '正在連線到 ${dev.platformName.isNotEmpty ? dev.platformName : dev.remoteId.str}…',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _successOverlay() {
    final dev = _connectedDevice!;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true, // 不攔截點擊
        child: Container(
          color: Colors.black38,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 96),
                const SizedBox(height: 8),
                Text(
                  '已連線到 ${dev.platformName.isNotEmpty ? dev.platformName : dev.remoteId.str}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// —— 波紋背景 —— //

class _RippleBackground extends StatelessWidget {
  final Animation<double> animation;
  const _RippleBackground({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final waves = List.generate(3, (i) => i);
        return CustomPaint(
          painter: _RipplePainter(progress: animation.value, waveCount: waves.length),
        );
      },
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final int waveCount;
  _RipplePainter({required this.progress, required this.waveCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < waveCount; i++) {
      final p = (progress + i / waveCount) % 1.0;
      final radius = lerpDouble(60, size.shortestSide * 0.6, p)!;
      final opacity = (1.0 - p).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withOpacity(opacity * 0.15);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.waveCount != waveCount;
  }
}
