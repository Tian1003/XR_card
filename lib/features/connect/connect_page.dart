// 📁 lib/features/connect/connect_page.dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/features/exchange/card_exchange_page.dart';

import 'bluetooth_connecting_page.dart';

enum ConnectMode { none, bluetooth, qr, scanner }

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  ConnectMode _mode = ConnectMode.none;
  final MobileScannerController _scannerController = MobileScannerController();

  // 取使用者 qr_code_url
  final _svc = SupabaseService(Supabase.instance.client);
  UserCompleteProfile? _user;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
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

  Future<void> _processQRToken(String token) async {
    try {
      await _scannerController.stop();
      final userData = await _svc.getUserByQRToken(token);

      if (userData != null && userData.userId != null) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CardExchangePage(peerUserId: userData.userId!),
          ),
        );
        if (!mounted) return;
        _switchMode(ConnectMode.qr);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無效的 QR 碼')));
        _switchMode(ConnectMode.qr);
      }
    } catch (e) {
      debugPrint('處理 QR 碼錯誤: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('處理 QR 碼時出錯: $e')));
      _switchMode(ConnectMode.qr);
    }
  }

  void _switchMode(ConnectMode mode) => setState(() => _mode = mode);

  String buildInviteUrl(String token) =>
      'https://yourapp.com/add/$token'; // 之後替換成正式網址

  // 掃描結果處理
  void _onQRCodeDetected(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final String? code = barcode.rawValue;
      if (code == null || code.isEmpty) continue;

      final uri = Uri.tryParse(code);
      if (uri != null &&
          uri.pathSegments.length > 1 &&
          uri.pathSegments[0] == 'add') {
        final token = uri.pathSegments[1];
        _processQRToken(token);
        break;
      }
    }
  }

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
      case ConnectMode.scanner:
        return _buildQRScanner();
      case ConnectMode.none:
        return _buildBluetooth();
    }
  }

  // ========= Bluetooth 區 =========
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

  // ========= QR Code 區 =========
  Widget _buildQRCode() {
    final token = _user?.qrCodeUrl?.trim();
    final hasToken = (token != null && token.isNotEmpty);
    final String? url = hasToken ? buildInviteUrl(token!) : null;

    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 右上：分割膠囊（左掃描／右分享）
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 20, bottom: 12),
                  child: _SplitActionButton(
                    shareEnabled: hasToken && !_loadingUser,
                    onScan: () {
                      HapticFeedback.selectionClick();
                      _switchMode(ConnectMode.scanner);
                    },
                    onShare: () async {
                      if (url == null) return;
                      HapticFeedback.lightImpact();
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已複製邀請連結')));
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Neumorphic QR 卡片
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

            // 下方模式切換
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

  // ========= 掃描頁 =========
  Widget _buildQRScanner() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.primary),
                  onPressed: () => _switchMode(ConnectMode.qr),
                ),
                const Expanded(
                  child: Text(
                    '掃描 QR 碼',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _onQRCodeDetected,
            ),
          ),
        ],
      ),
    );
  }

  // ========= 元件：Neumorphic 模式按鈕 =========
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
}

/// ===== 額外類別：左右分割膠囊（左：掃描／右：分享） =====
class _SplitActionButton extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onShare;
  final bool shareEnabled;

  const _SplitActionButton({
    required this.onScan,
    required this.onShare,
    this.shareEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // 外框：沿用你的 Neumorphic 風格
    return Opacity(
      opacity: shareEnabled ? 1 : 0.6,
      child: Container(
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
            // 左半：相機掃描
            _HalfButton(
              onTap: onScan,
              iconData: Icons.qr_code_scanner_rounded,
              label: 'Scan',
              rightBorder: true,
            ),
            // 右半：分享
            _HalfButton(
              onTap: shareEnabled ? onShare : null,
              iconData: Icons.ios_share,
              label: 'Share',
              rightBorder: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _HalfButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData iconData;
  final String label;
  final bool rightBorder;

  const _HalfButton({
    required this.onTap,
    required this.iconData,
    required this.label,
    this.rightBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.horizontal(
        left: rightBorder ? const Radius.circular(12) : Radius.zero,
        right: rightBorder ? Radius.zero : const Radius.circular(12),
      ),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.horizontal(
            left: rightBorder ? const Radius.circular(12) : Radius.zero,
            right: rightBorder ? Radius.zero : const Radius.circular(12),
          ),
          border: rightBorder
              ? const Border(
                  right: BorderSide(color: Color(0x1A000000), width: 1), // 中線
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 左側圓形深綠底 icon（呼應你的設計）
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(iconData, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
