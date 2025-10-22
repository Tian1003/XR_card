import 'dart:async'; // 用於 Timer
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    as fbp; // 為了 ScanResult

import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/services/ai_service.dart';
import 'package:my_app/services/bluetooth_service.dart';
import 'package:my_app/services/nearby_presence.dart';
import 'package:my_app/core/widgets/expanding_fab.dart';
import 'package:my_app/core/widgets/xr_business_card.dart';

class XrSimulatorPage extends StatefulWidget {
  const XrSimulatorPage({super.key});

  @override
  State<XrSimulatorPage> createState() => _XrSimulatorPageState();
}

class _XrSimulatorPageState extends State<XrSimulatorPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraInitialized = false;

  late final SupabaseService _supabaseService;
  late final AiService _aiService;
  bool _isAnalyzing = false;

  // --- (修改) 藍牙與好友偵測 ---
  final BluetoothService _btService = BluetoothService.I;
  Timer? _scanTimer; // 用於週期性掃描
  Set<int> _friendIds = {}; // 我已接受的好友 ID 列表 (僅 ID)
  Map<int, UserCompleteProfile> _allFriendProfiles = {}; // (修改) 預先載入 *所有* 好友的資料
  Set<int> _nearbyFriendIds = {}; // (修改) *當前* 偵測到的好友 ID
  // --- (修改) 結束 ---

  @override
  void initState() {
    super.initState();
    _supabaseService = SupabaseService(Supabase.instance.client);
    _aiService = AiService();
    _initializeCamera();

    // --- (保留) 藍牙好友偵測 ---
    WidgetsBinding.instance.addObserver(this); // 監聽 App 生命週期
    _btService.results.addListener(_onScanResultsUpdated); // 監聽掃描結果
    _loadFriendListAndStartScanning(); // 載入好友並開始掃描
    // --- (保留) 結束 ---
  }

  // --- (保留) App 生命週期管理 ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      // App 回到前景，重啟相機和掃描
      debugPrint("XR: App resumed, restarting camera and scan...");
      _initializeCamera();
      _loadFriendListAndStartScanning(); // 重新載入並開始掃描
    } else if (state == AppLifecycleState.paused) {
      // App 進入背景，釋放相機和停止掃描
      debugPrint("XR: App paused, disposing camera and stopping scan...");
      _controller?.dispose(); // 釋放相機
      _isCameraInitialized = false; // 標記相機
      _stopPeriodicScans(); // 停止藍牙掃描
    }
  }
  // --- (保留) 結束 ---

  // --- (恢復) 用於執行企業分析 ---
  Future<void> _runCompanyAnalysis(UserCompleteProfile profile) async {
    if (_isAnalyzing) return;

    final companyName = profile.company;
    if (companyName == null || companyName.trim().isEmpty) {
      _showSnackBar("${profile.username} 未提供公司名稱，無法分析。");
      return;
    }

    setState(() => _isAnalyzing = true);
    _showSnackBar('正在為 ${companyName} 進行企業分析...');

    // --- 新增：自動重試邏輯 ---
    const maxRetries = 2; // 最多重試 2 次
    String? result;
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

  // --- (修改) 藍牙好友偵測邏輯 ---

  Future<void> _loadFriendListAndStartScanning() async {
    // 1. 確保藍牙已開啟
    await _btService.waitUntilPoweredOn(timeout: const Duration(seconds: 10));

    // 2. 獲取好友 ID 列表
    try {
      _friendIds = await _supabaseService.fetchContactUserIds(
        me: _supabaseService.myUserId,
        includePending: false, // 只偵測已接受的好友
      );
      debugPrint('XR: 好友 ID 列表載入: ${_friendIds.length} 人');

      // (新增) 立即預先載入所有好友的 Profile
      if (_friendIds.isNotEmpty) {
        await _fetchAllFriendProfiles(_friendIds);
      }
    } catch (e) {
      debugPrint("XR: 載入好友列表失敗: $e");
      if (mounted) _showSnackBar("無法載入好友列表");
    }

    // 3. 開始週期性掃描
    _startPeriodicScans();
  }

  // (新增) 預先獲取所有好友的 Profile
  Future<void> _fetchAllFriendProfiles(Set<int> friendIds) async {
    try {
      final profiles = await _supabaseService.fetchProfilesByIds(friendIds);
      if (!mounted) return;
      // 將 List 轉為 Map，方便後續快速查找
      _allFriendProfiles = {for (var p in profiles) p.userId: p};
      debugPrint('XR: 已預先載入 ${_allFriendProfiles.length} 位好友的 Profile');
    } catch (e) {
      debugPrint("XR: 預先載入好友 Profile 失敗: $e");
    }
  }

  void _startPeriodicScans() {
    if (!mounted) return;
    if (_scanTimer != null && _scanTimer!.isActive) {
      debugPrint("XR: 掃描已在執行中");
      return;
    }

    debugPrint("XR: 開始週期性掃描...");
    _scanNow(); // 立即掃描一次
    _scanTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      _scanNow();
    });
  }

  void _stopPeriodicScans() {
    debugPrint("XR: 停止週期性掃描");
    _scanTimer?.cancel();
    _scanTimer = null;
    _btService.stopScan();
  }

  void _scanNow() {
    if (!mounted || _btService.isScanning.value) return;
    debugPrint("XR: 觸發掃描...");
    _btService.startScan();
  }

  // (修改) 核心：當藍牙結果更新時
  void _onScanResultsUpdated() {
    if (!mounted) return;

    final Set<int> currentlyDetectedFriendIds = {};

    for (final result in _btService.results.value) {
      final parsed = NearbyPresence.parseAdvAll(result.advertisementData);
      if (parsed == null) continue;

      final detectedUserId = parsed.userId;

      // 判斷是否為「非本人」的「好友」
      if (detectedUserId != _supabaseService.myUserId &&
          _friendIds.contains(detectedUserId)) {
        currentlyDetectedFriendIds.add(detectedUserId);
      }
    }

    // (修改) 邏輯簡化：
    // 只有在「當前偵測到的好友 Set」與「上次的 Set」內容不同時，才觸發 setState
    if (!const SetEquality().equals(
      _nearbyFriendIds,
      currentlyDetectedFriendIds,
    )) {
      setState(() {
        _nearbyFriendIds = currentlyDetectedFriendIds;
        debugPrint("XR: 附近好友更新: $_nearbyFriendIds");
      });
    }
  }

  // --- 相機邏輯 ---
  Future<void> _initializeCamera() async {
    if (_isCameraInitialized) return;
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

    // --- 藍牙好友偵測 ---
    WidgetsBinding.instance.removeObserver(this);
    _stopPeriodicScans();
    _btService.results.removeListener(_onScanResultsUpdated);

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              // (修改) 遍歷 ID Set，並從 Map 中取出 Profile
              children: _nearbyFriendIds.map((friendId) {
                // 從預先載入的 Map 中查找 Profile
                final profile = _allFriendProfiles[friendId];

                // 如果 Profile 尚未載入完成 (理論上應該很快)，則不顯示
                if (profile == null) {
                  return const SizedBox.shrink();
                }

                // (保留) 顯示名片
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: XrBusinessCard(
                    profile: profile,
                    onAnalyzePressed: () => _runCompanyAnalysis(profile),
                    onRecordPressed: () =>
                        _showSnackBar("點擊了 ${profile.username} 的對話回顧"),
                    onChatPressed: () =>
                        _showSnackBar("點擊了 ${profile.username} 的話題建議"),
                  ),
                );
              }).toList(),
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
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
