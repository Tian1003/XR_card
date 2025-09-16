// 📁 lib/features/connect/connect_page.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter/services.dart'; // ← 新增
import 'bluetooth_connecting_page.dart';

enum ConnectMode { none, bluetooth, qr }

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  ConnectMode _mode = ConnectMode.none;

  void _switchMode(ConnectMode mode) {
    setState(() {
      _mode = mode;
    });
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
      case ConnectMode.none:
        return _buildBluetooth();
    }
  }

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
              _modeButton('Bluetooth', isActive: true),
              _modeButton(
                'QR Code',
                isActive: false,
                onTap: () => _switchMode(ConnectMode.qr),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQRCode() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () {},
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Image.asset('assets/icons/sample_qrcode.png', width: 180),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _modeButton(
                'Bluetooth',
                isActive: false,
                onTap: () => _switchMode(ConnectMode.bluetooth),
              ),
              _modeButton('QR Code', isActive: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
    String label, {
    required bool isActive,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 167,
        height: 65,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.black54,
              fontWeight: FontWeight.bold,
              fontSize: 26,
            ),
          ),
        ),
      ),
    );
  }
}
