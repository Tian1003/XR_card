import 'package:flutter/material.dart';

/// 單一平台的設定結構
class PlatformStyle {
  final Color color;
  final dynamic icon; // 可以是 String 或 IconData
  final bool isText;

  const PlatformStyle({
    required this.color,
    required this.icon,
    required this.isText,
  });
}

/// 平台樣式設定工具
class SocialPlatformConfig {
  static const Map<String, PlatformStyle> _data = {
    'linkedin': PlatformStyle(
      color: Color(0xFF0077B5),
      icon: 'in', // 用文字
      isText: true,
    ),
    'facebook': PlatformStyle(
      color: Color(0xFF1877F2),
      icon: Icons.facebook,
      isText: false,
    ),
    'instagram': PlatformStyle(
      color: Color(0xFFE4405F),
      icon: Icons.camera_alt,
      isText: false,
    ),
    'twitter': PlatformStyle(
      color: Color(0xFF1DA1F2),
      icon: Icons.flutter_dash,
      isText: false,
    ),
    'github': PlatformStyle(
      color: Color(0xFF333333),
      icon: Icons.code,
      isText: false,
    ),
    'website': PlatformStyle(
      color: Color(0xFF4285F4),
      icon: Icons.language,
      isText: false,
    ),
  };

  /// 依平台名稱取得設定
  static PlatformStyle? get(String platform) {
    return _data[platform.toLowerCase()];
  }
}
