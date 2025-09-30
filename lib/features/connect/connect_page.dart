// 📁 lib/features/connect/connect_page.dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'package:flutter/services.dart'; // ← 新增
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/user_complete_profile.dart';
import '../../data/supabase_services.dart';
import 'bluetooth_connecting_page.dart';

enum ConnectMode { none, bluetooth, qr }

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  ConnectMode _mode = ConnectMode.none;

  // 取使用者 qr_code_url
  final _svc = SupabaseService(Supabase.instance.client);
  UserCompleteProfile? _user;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final data = await _svc.fetchUserCompleteProfile();
      if (!mounted) return;
      setState(() {
        _user = data;
        _loadingUser = false;
      });
    } catch (e) {
      debugPrint('load user error: $e');
      if (!mounted) return;
      setState(() => _loadingUser = false);
    }
  }

  void _switchMode(ConnectMode mode) => setState(() => _mode = mode);

  String buildInviteUrl(String token) => 'https://yourapp.com/add/$token';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case ConnectMode.bluetooth:
        return _buildBluetooth();
      case ConnectMode.qr:
        return _buildQRCode();
      case ConnectMode.none:
        return _buildBluetooth();
    }
  }

  // ===================== Bluetooth 區 =====================
  Widget _buildBluetooth() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Tap to connect',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 32),

          // 圓形藍牙按鈕
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BluetoothConnectingPage(
                    onCancel: () => Navigator.pop(context),
                  ),
                ),
              );
            },
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2C6B6A), AppColors.primary],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(4, 8),
                  ),
                  BoxShadow(
                    color: Colors.white24,
                    blurRadius: 8,
                    offset: Offset(-4, -4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.bluetooth, size: 200, color: Colors.white),
              ),
            ),
          ),

          const SizedBox(height: 125),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _neumorphicModeButton(
                label: 'Bluetooth',
                active: true,
                onTap: null, // 目前已在此頁
              ),
              _neumorphicModeButton(
                label: 'QR Code',
                active: false,
                onTap: () => _switchMode(ConnectMode.qr),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== QR Code 區 =====================
  Widget _buildQRCode() {
    final token = _user?.qrCodeUrl?.trim();
    final hasToken = (token != null && token.isNotEmpty);
    final url = hasToken ? buildInviteUrl(token!) : null;

    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 右上 Share（參考設計稿：圓角 + 陰影 + 左側圓形 icon）
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, bottom: 12),
                child: _shareButton(
                  enabled: hasToken && !_loadingUser,
                  onTap: () async {
                    if (url == null) return;
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已複製邀請連結')));
                  },
                ),
              ),
            ),

            // Neumorphic QR 卡片（外灰內白，圓角+柔光投影）
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEDED), // 淺灰背景
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-6, -6),
                    blurRadius: 12,
                  ),
                  BoxShadow(
                    color: Color(0x33000000),
                    offset: Offset(6, 6),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: _loadingUser
                    ? const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : hasToken
                    ? QrImageView(
                        data: url!,
                        version: QrVersions.auto,
                        size: 220,
                        gapless: true,
                        backgroundColor: Colors.white,
                      )
                    : const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(child: Text('尚未產生 QR 代碼')),
                      ),
              ),
            ),

            const SizedBox(height: 40),

            // 下方模式切換（Neumorphic 風格）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _neumorphicModeButton(
                  label: 'Bluetooth',
                  active: false,
                  onTap: () => _switchMode(ConnectMode.bluetooth),
                ),
                _neumorphicModeButton(
                  label: 'QR Code',
                  active: true,
                  onTap: null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===================== 元件：Neumorphic 按鈕 =====================
  Widget _neumorphicModeButton({
    required String label,
    required bool active,
    VoidCallback? onTap,
  }) {
    // 依設計稿：未選取為淺灰、選取為主綠色；皆帶柔和陰影
    final bg = active ? AppColors.primary : Colors.grey.shade300;
    final fg = active ? Colors.white : const Color(0xFF3C6664);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 167,
        height: 65,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.white,
              offset: Offset(-4, -4),
              blurRadius: 6,
            ),
            BoxShadow(
              color: Color(0x33000000),
              offset: Offset(4, 4),
              blurRadius: 6,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  // ===================== 元件：Share Neumorphic =====================
  Widget _shareButton({required bool enabled, required VoidCallback onTap}) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEDEDED),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.white,
                offset: Offset(-4, -4),
                blurRadius: 6,
              ),
              BoxShadow(
                color: Color(0x33000000),
                offset: Offset(4, 4),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 左側圓形 icon（深綠底白 icon）
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.ios_share,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Share',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
