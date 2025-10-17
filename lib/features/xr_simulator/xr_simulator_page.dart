import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/services/ai_service.dart';
import 'package:my_app/core/widgets/expanding_fab.dart';
import 'package:my_app/core/widgets/xr_business_card.dart';

class XrSimulatorPage extends StatefulWidget {
  const XrSimulatorPage({super.key});

  @override
  State<XrSimulatorPage> createState() => _XrSimulatorPageState();
}

class _XrSimulatorPageState extends State<XrSimulatorPage> {
  CameraController? _controller;
  bool _isCameraInitialized = false;

  // 用於獲取使用者資料
  late final SupabaseService _supabaseService;
  UserCompleteProfile? _userProfile;

  late final AiService _aiService;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _supabaseService = SupabaseService(Supabase.instance.client);
    _aiService = AiService();
    _initializeCamera();
    _loadUserData();
  }

  // 用於執行企業分析
  Future<void> _runCompanyAnalysis() async {
    if (_isAnalyzing) return;

    setState(() => _isAnalyzing = true);
    _showSnackBar('正在為您進行企業分析...');

    final companyName = _userProfile?.company ?? '';
    String? result;

    // --- 新增：自動重試邏輯 ---
    const maxRetries = 2; // 最多重試 2 次
    for (int i = 0; i <= maxRetries; i++) {
      result = await _aiService.analyzeCompany(companyName);

      // 如果分析成功 (不是 null 也不是特定錯誤訊息)，就跳出迴圈
      if (result != null && !result.contains('UNAVAILABLE')) {
        break;
      }

      // 如果還有重試次數，就等待一下再重試
      if (i < maxRetries) {
        debugPrint('分析失敗 (模型忙碌)，將在 2 秒後重試... (${i + 1}/$maxRetries)');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    // --- 重試邏輯結束 ---

    debugPrint('===== Gemini 企業分析結果 =====');
    debugPrint(result);
    debugPrint('=============================');

    if (mounted) {
      setState(() => _isAnalyzing = false);

      // 為了避免顯示原始錯誤碼，我們做個判斷
      final displayResult = (result != null && result.contains('UNAVAILABLE'))
          ? '模型目前忙碌中，請稍後再試。'
          : result ?? '沒有分析結果。';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('「$companyName」分析報告'),
          content: SingleChildScrollView(child: Text(displayResult)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _controller = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      } else {
        _showErrorDialog("找不到可用的相機");
      }
    } catch (e) {
      _showErrorDialog("相機初始化失敗: $e");
    }
  }

  Future<void> _loadUserData() async {
    try {
      final profile = await _supabaseService.fetchUserCompleteProfile();
      if (mounted) {
        setState(() {
          _userProfile = profile;
        });
      }
    } catch (e) {
      debugPrint("讀取使用者資料失敗: $e");
    }
  }

  void _showErrorDialog(String message) {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('錯誤'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 底層：相機預覽
          if (_isCameraInitialized && _controller != null)
            Positioned.fill(child: CameraPreview(_controller!))
          else
            const Center(child: CircularProgressIndicator()),

          // 上層：固定的 UI 元件
          _buildOverlayUI(),
        ],
      ),
    );
  }

  Widget _buildOverlayUI() {
    final orientation = MediaQuery.of(context).orientation; // 螢幕方向
    final screenWidth = MediaQuery.of(context).size.width; // 螢幕寬度
    final isLandscape = orientation == Orientation.landscape; // 是否為橫向螢幕

    // 將所有覆蓋層 UI 包裹在 SafeArea 中，自動避開動態島和系統 UI
    return SafeArea(
      child: Stack(
        children: [
          // 左上角的返回按鈕 (微調 top 和 left 以貼合 SafeArea)
          Positioned(
            top: 0,
            left: 8,
            child: IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // 右下角：懸浮名片 (對齊 SafeArea 右下)
          Positioned(
            bottom: 0,
            right: 0,
            left: isLandscape ? screenWidth * 0.55 : null,
            width: isLandscape ? null : screenWidth * 0.75,
            child: XrBusinessCard(
              profile: _userProfile,
              onAnalyzePressed: _runCompanyAnalysis, // 企業分析
              onRecordPressed: () => _showSnackBar("點擊了對話回顧"), // 對話回顧
              onChatPressed: () => _showSnackBar("點擊了話題建議"), // 話題建議
            ),
          ),

          // 名片右上方可展開的功能按鈕
          Positioned(
            bottom: isLandscape ? 170 : 170, // 根據螢幕方向調整按鈕距離底部的高度，使其大致對齊名片頂部
            right: 8,
            child: ExpandingFab(
              actions: [
                FabAction(
                  label: "建立對話錄製",
                  icon: Icons.lightbulb_outline,
                  onPressed: () => _showSnackBar("點擊了建立對話錄製"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
