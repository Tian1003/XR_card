import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:my_app/services/summary_service.dart';


import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/services/ai_service.dart';
import 'package:my_app/services/bluetooth_service.dart';
import 'package:my_app/services/nearby_presence.dart';
import 'package:my_app/services/speech_to_text.dart';
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

    // --- 新增：摘要服務，放在類別欄位 ---
    final SummaryService _summaryService = SummaryService();

    // --- 藍牙與好友偵測 ---
    final BluetoothService _btService = BluetoothService.I;
    final NearbyPresence _nearbyPresence = NearbyPresence.I;
    Timer? _scanTimer;
    Set<int> _friendIds = {};
    Map<int, UserCompleteProfile> _allFriendProfiles = {};
    Set<int> _nearbyFriendIds = {};

    // --- 錄音 / STT 狀態 ---
    final AudioRecorder _recorder = AudioRecorder();
    bool _isRecording = false;
    String? _recordPath;
    DateTime? _recordStartedAt;
    final SpeechToTextService _stt = SpeechToTextService();

    Future<T> _withTimeout<T>(Future<T> future, Duration timeout, String tag) async {
      try {
        return await future.timeout(timeout, onTimeout: () {
          throw TimeoutException('$tag timeout after ${timeout.inSeconds}s');
        });
      } catch (e, st) {
        debugPrint('$tag failed: $e');
        debugPrint('$tag stack: $st');
        rethrow;
      }
    }


  @override
  void initState() {
    super.initState();
    _supabaseService = SupabaseService(Supabase.instance.client);
    _aiService = AiService();
    _initializeCamera();

    // --- 藍牙好友偵測 ---
    WidgetsBinding.instance.addObserver(this); // 監聽 App 生命週期
    _btService.results.addListener(_onScanResultsUpdated); // 監聽掃描結果
    _loadFriendListAndStartScanning(); // 載入好友並開始掃描
    _warmupWhisper();
  }

  void _warmupWhisper() async {
    try {
      // 如果你的 SpeechToTextService 有 version()，可用它確保插件 ready
      // 沒有也無所謂，這只是軟預熱
      // ignore: unused_local_variable
      final v = await _stt.version();
      debugPrint('Whisper ready');
    } catch (e) {
      debugPrint('Whisper warmup failed: $e');
    }
  }


  // --- App 生命週期管理 ---
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
      _nearbyPresence.stop(); // 停止廣播

      // 若正在錄音就停止
      _forceStopRecordingIfNeeded();
    }
  }

  // --- 強制停止錄音（在背景/離開頁面時保護） ---
  Future<void> _forceStopRecordingIfNeeded() async {
    if (_isRecording) {
      try { await _recorder.stop(); } catch (_) {}
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _debugFetchLatestRecord() async {
    try {
      final rows = await Supabase.instance.client
          .from('conversation_records')
          .select('record_id, contact_id, content, created_at')
          .eq('contact_id', 4)
          .order('record_id', ascending: false)
          .limit(1);

      if (rows is List && rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        final contentLen = (row['content'] as String?)?.length ?? 0;
        debugPrint('DB: 最新 record_id=${row['record_id']} '
            'contact_id=${row['contact_id']} content_len=$contentLen '
            'created_at=${row['created_at']}');
        _showSnackBar("最新一筆 record_id=${row['record_id']} 已寫入");
      } else {
        _showSnackBar("抓不到最新一筆資料（contact_id=4）");
      }
    } catch (e) {
      debugPrint("DB: 讀最新一筆失敗: $e");
    }
  }




  // --- 用於執行企業分析 ---
  Future<void> _runCompanyAnalysis(UserCompleteProfile profile) async {
    if (_isAnalyzing) return;

    final companyName = profile.company;
    if (companyName == null || companyName.trim().isEmpty) {
      _showSnackBar("${profile.username} 未提供公司名稱，無法分析。");
      return;
    }

    setState(() => _isAnalyzing = true);
    _showSnackBar('正在為 ${companyName} 進行企業分析...');

    // --- 自動重試邏輯 ---
    const maxRetries = 2; // 最多重試 2 次
    String? result;
    for (int i = 0; i <= maxRetries; i++) {
      result = await _aiService.analyzeCompany(companyName);

      // 如果分析成功 (不是 null 也不是特定錯誤訊息)，就跳出迴圈
      if (result != null && !result.contains('UNAVAILABLE')) {
        break;
      }

      if (i < maxRetries) {
        debugPrint('分析失敗 (模型忙碌)，將在 2 秒後重試... (${i + 1}/$maxRetries)');
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    debugPrint('===== Gemini 企業分析結果 =====');
    debugPrint(result);
    debugPrint('=============================');

    if (mounted) {
      setState(() => _isAnalyzing = false);

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

  // --- 藍牙好友偵測邏輯 ---
  Future<void> _loadFriendListAndStartScanning() async {
    // 1. 確保藍牙已開啟
    await _btService.waitUntilPoweredOn(timeout: const Duration(seconds: 10));

    // 應在載入好友ID之前啟動，因為 NearbyPresence.start() 依賴 Supabase 登入狀態
    try {
      await _nearbyPresence.start();
      debugPrint("XR: 已開始廣播自己的 ID");
    } catch (e) {
      debugPrint("XR: 啟動廣播失敗: $e");
      if (mounted) _showSnackBar("無法啟動廣播功能");
    }

    // 2. 獲取好友 ID 列表
    try {
      _friendIds = await _supabaseService.fetchContactUserIds(
        me: _supabaseService.myUserId,
        includePending: false, // 只偵測已接受的好友
      );
      debugPrint('XR: 好友 ID 列表載入: ${_friendIds.length} 人');

      // 立即預先載入所有好友的 Profile
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

  // --- 預先獲取所有好友的 Profile ---
  Future<void> _fetchAllFriendProfiles(Set<int> friendIds) async {
    try {
      final profiles = await _supabaseService.fetchProfilesByIds(friendIds);
      if (!mounted) return;
      _allFriendProfiles = {for (var p in profiles) p.userId: p};
      debugPrint('XR: 已預先載入 ${_allFriendProfiles.length} 位好友的 Profile');
    } catch (e) {
      debugPrint("XR: 預先載入好友 Profile 失敗: $e");
    }
  }

  // --- 開始週期性掃描 ---
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

  // 核心：當藍牙結果更新時
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

  // ====== 錄音：開始/停止 + Whisper 轉錄 + Supabase 寫入 ======
  Future<String> _genWavPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final filename = "conv_${DateTime.now().millisecondsSinceEpoch}.wav";
    return "${dir.path}/$filename";
  }

  // 停止錄音 → 轉文字 → Insert DB（contact_id=4）
  Future<void> _toggleRecording() async {
    try {
      if (!_isRecording) {
        // ====== 開始錄音 ======
        if (!await _recorder.hasPermission()) {
          _showSnackBar("沒有錄音權限");
          return;
        }
        final path = await _genWavPath();
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _recordPath = path;
          _recordStartedAt = DateTime.now();
        });
        _showSnackBar("開始錄音…（再次點擊停止）");
      } else {
        // ====== 停止錄音 ======
        final p = await _recorder.stop();
        setState(() => _isRecording = false); // ← 停止錄音後 UI 還原
        if (p == null) {
          _showSnackBar("未取得錄音檔");
          return;
        }
        _recordPath = p;

        // 時長
        final durationSec = _recordStartedAt == null
            ? 0
            : DateTime.now().difference(_recordStartedAt!).inSeconds;

        // ====== STT（Whisper 離線）=====
        String transcript = '';
        try {
          final stt = await _withTimeout(
            _stt.transcribeFile(_recordPath!, durationSec: durationSec),
            const Duration(seconds: 180),
            'STT',
          );
          transcript = stt.text;
          debugPrint("STT: transcript.length=${transcript.length}");
        } catch (e) {
          debugPrint("STT: 轉文字失敗：$e");
          transcript = '（STT 失敗或逾時：$e）';
        }

        // ====== 摘要（可選：有金鑰才會成功）======
        String? summary;
        try {
          summary = await _summaryService.summarize(transcript);
          debugPrint("AI summary: ${summary?.length ?? 0} chars");
        } catch (e) {
          debugPrint("AI: 摘要失敗：$e");
          summary = null; // 失敗就不要擋主流程
        }

        // ====== 以 contact_id 覆蓋式寫入（有就 update，沒有才 insert）=====
        try {
          final id = await _upsertConversationRecordByContact(
            contactId: 4, // 這次測試固定 4
            content: transcript.isEmpty ? '（無內容）' : transcript,
            summary: summary, // 可能為 null
            eventName: "對話錄音",
            audioDurationSec: durationSec,
          );
          _showSnackBar("DB 已更新（record_id=$id）");
          debugPrint("DB: upsert OK record_id=$id");
        } catch (e, st) {
          _showSnackBar("寫入資料庫失敗：$e");
          debugPrint("DB: upsert failed: $e");
          debugPrint("DB: stack: $st");
        }

        // （可選）抓回最新一筆確認
        await _debugFetchLatestRecord();

      } // ← 關閉 if-else（你原本少了這個）
    } catch (e) { // ← 關閉外層 try（你原本也少了）
      setState(() => _isRecording = false);
      _showSnackBar("錄音/轉錄/寫入失敗：$e");
    }

    try {
      if (_recordPath != null) {
        final f = File(_recordPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}

  }


  Future<void> _openConversationReview(int friendUserId) async {
    try {
      final myId = _supabaseService.myUserId;

      // 1) 找我們兩人的 contact_id（任一方向）
      final contacts = await Supabase.instance.client
          .from('contacts')
          .select('contact_id, requester_id, friend_id, status')
          .or('and(requester_id.eq.$myId,friend_id.eq.$friendUserId),and(requester_id.eq.$friendUserId,friend_id.eq.$myId)')
          .eq('status', 'accepted')   // 只看已接受的關係
          .limit(1);

      if (contacts is! List || contacts.isEmpty) {
        _showSnackBar('尚未成為好友，沒有對話回顧。');
        return;
      }
      final contactId = contacts.first['contact_id'] as int;

      // 2) 抓最後一筆對話紀錄
      final rows = await Supabase.instance.client
          .from('conversation_records')
          .select('record_id, summary, content, record_time, updated_at')
          .eq('contact_id', contactId)
          .order('record_id', ascending: false)
          .limit(1);

      if (rows is! List || rows.isEmpty) {
        _showSnackBar('目前沒有與此聯絡人的對話紀錄。');
        return;
      }

      final rec = rows.first as Map<String, dynamic>;
      final summary = (rec['summary'] as String?)?.trim();
      final content = (rec['content'] as String?)?.trim();
      final when = rec['updated_at'] ?? rec['record_time'];

      // 3) 顯示 Dialog
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('對話回顧'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (when != null) Text('時間：$when\n'),
                  Text(
                    summary?.isNotEmpty == true ? '摘要：\n$summary' : '摘要：無',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content?.isNotEmpty == true ? '逐字稿：\n$content' : '逐字稿：無',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('關閉'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint('Review 打開失敗：$e');
      _showSnackBar('載入對話回顧失敗');
    }
  }


  Future<int> _upsertConversationRecordByContact({
    required int contactId,
    required String content,
    String? summary,
    String? eventName,
    int? audioDurationSec,
  }) async {
    final now = DateTime.now().toUtc();

    // 先找舊資料（這裡選擇「最後一筆」當作要覆蓋的對象）
    final existing = await Supabase.instance.client
        .from('conversation_records')
        .select('record_id')
        .eq('contact_id', contactId)
        .order('record_id', ascending: false)
        .limit(1);

    if (existing is List && existing.isNotEmpty) {
      final rid = existing.first['record_id'] as int;
      final updatePayload = {
        'content': content,
        'summary': summary,
        'event_name': eventName,
        'audio_duration': audioDurationSec,
        'record_time': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final row = await Supabase.instance.client
          .from('conversation_records')
          .update(updatePayload)
          .eq('record_id', rid)
          .select('record_id')
          .single();

      return row['record_id'] as int;
    } else {
      // 沒有任何既有紀錄 → 新增
      final insertPayload = {
        'contact_id': contactId,
        'content': content,
        'summary': summary,
        'event_name': eventName,
        'audio_duration': audioDurationSec,
        'location_type': 'physical',
        'record_time': now.toIso8601String(),
      };

      final row = await Supabase.instance.client
          .from('conversation_records')
          .insert(insertPayload)
          .select('record_id')
          .single();

      return row['record_id'] as int;
    }
  }


  @override
  void dispose() {
    _controller?.dispose();

    // --- 藍牙好友偵測 ---
    WidgetsBinding.instance.removeObserver(this);
    _stopPeriodicScans();
    _btService.results.removeListener(_onScanResultsUpdated);
    _nearbyPresence.stop(); // 停止廣播

    _forceStopRecordingIfNeeded();

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
          // 左上角的返回按鈕
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

          // 右下角：懸浮名片
          Positioned(
            bottom: 0,
            right: 0,
            left: isLandscape ? screenWidth * 0.55 : null,
            width: isLandscape ? null : screenWidth * 0.75,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _nearbyFriendIds.map((friendId) {
                final profile = _allFriendProfiles[friendId];
                if (profile == null) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: XrBusinessCard(
                    profile: profile,
                    onAnalyzePressed: () => _runCompanyAnalysis(profile),
                    onRecordPressed: () =>
                        _openConversationReview(profile.userId),
                    onChatPressed: () =>
                        _showSnackBar("點擊了 ${profile.username} 的話題建議"),
                  ),
                );
              }).toList(),
            ),
          ),

          // 名片右上：可展開功能按鈕（錄音切換）
          Positioned(
            bottom: isLandscape ? 170 : 170,
            right: 8,
            child: ExpandingFab(
              actions: [
                FabAction(
                  label: _isRecording ? "停止並轉錄" : "建立對話錄製",
                  icon: _isRecording ? Icons.stop : Icons.mic,
                  onPressed: _toggleRecording,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
