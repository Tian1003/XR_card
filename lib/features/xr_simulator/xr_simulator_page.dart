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
import 'package:my_app/services/google_search_service.dart';
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
  late final GoogleSearchService _googleSearchService;
  late final AiService _aiService;
  bool _isAnalyzing = false;
  String _companyAnalysisResult = '';

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

  // --- 「話題建議」的狀態變數 ---
  List<String> _dialogSuggestions = [];
  bool _isLoadingSuggestions = false;
  String? _suggestionError;

  Future<T> _withTimeout<T>(
    Future<T> future,
    Duration timeout,
    String tag,
  ) async {
    try {
      return await future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('$tag timeout after ${timeout.inSeconds}s');
        },
      );
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
    _googleSearchService = GoogleSearchService();
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
      try {
        await _recorder.stop();
      } catch (_) {}
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _debugFetchLatestRecord() async {
    try {
      if (_nearbyFriendIds.isEmpty) {
        _showSnackBar("附近沒有好友，無法取得最新對話紀錄。");
        return;
      }

      // 1️⃣ 取目前最接近的好友 ID
      final friendUserId = _nearbyFriendIds.first;

      // 2️⃣ 找雙方的 contact_id
      final contactId = await _resolveContactIdForUser(friendUserId);
      if (contactId == null) {
        _showSnackBar("尚未與此好友建立聯絡人關係。");
        return;
      }

      // 3️⃣ 查詢該 contact_id 最新紀錄
      final rows = await Supabase.instance.client
          .from('conversation_records')
          .select('record_id, contact_id, content, summary, updated_at, record_time')
          .eq('contact_id', contactId)
          .order('record_id', ascending: false)
          .limit(1);

      if (rows is List && rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        final summary = (row['summary'] as String?)?.trim() ?? '（無摘要）';
        final content = (row['content'] as String?)?.trim() ?? '（無內容）';
        final when = row['updated_at'] ?? row['record_time'];
        debugPrint(
          'DB: 最新 record_id=${row['record_id']} '
          'contact_id=${row['contact_id']} summary_len=${summary.length} '
          'content_len=${content.length} created_at=$when',
        );
        _showSnackBar("最新一筆 record_id=${row['record_id']} 已抓取成功");
      } else {
        _showSnackBar("目前與該聯絡人沒有任何對話紀錄。");
      }
    } catch (e) {
      debugPrint("DB: 抓最新對話失敗: $e");
      _showSnackBar("讀取最新對話紀錄失敗");
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
      final displayResult = (result != null && result.contains('UNAVAILABLE'))
          ? '模型目前忙碌中，請稍後再試。'
          : result ?? '沒有分析結果。';

      setState(() {
        _isAnalyzing = false;
        if (!displayResult.contains('模型目前') &&
            !displayResult.contains('沒有分析結果')) {
          _companyAnalysisResult = displayResult;
        }
      });

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

  // --- 話題建議 ---
  Future<void> _fetchDialogSuggestions(UserCompleteProfile profile) async {
    if (_isLoadingSuggestions) return;
    setState(() {
      _isLoadingSuggestions = true;
      _suggestionError = null;
      _dialogSuggestions = [];
    });

    _showSuggestionsDialog(); // 顯示 Loading Dialog

    try {
      // 獲取公司名稱和職稱
      final companyName = profile.company;
      final jobTitle = profile.jobTitle;

      if (companyName == null || companyName.isEmpty) {
        throw Exception('未設定公司名稱');
      }

      String? companyInfo;
      List<String> newsSnippets = [];
      String? lastSummary;

      // 1. 獲取企業細節 (重用已分析的結果)
      if (_companyAnalysisResult.isNotEmpty) {
        companyInfo = _companyAnalysisResult;
      } else {
        companyInfo = null;
      }

      // 2. 獲取時事新聞 (傳入職稱)
      newsSnippets = await _fetchNews(companyName, jobTitle); // <--- 修改

      // 3. 獲取上次對話回顧 (Supabase)
      // [!] 提醒：您需要將 contactId 傳入此頁面
      // final int? currentContactId = widget.contactId;
      final int? currentContactId = await _resolveContactIdForUser(profile.userId); // 暫時用 null

      if (currentContactId != null) {
        try {
          lastSummary = await _supabaseService.fetchLatestConversationSummary(
            currentContactId,
          );
        } catch (e) {
          debugPrint("Error fetching summary: $e");
        }
      }

      // 4. 生成「開場白」 (傳入職稱)
      _dialogSuggestions = await _aiService.generateSuggestions(
        companyName,
        jobTitle,
        companyInfo,
        newsSnippets,
        lastSummary,
      );
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
      if (mounted) {
        setState(() {
          _suggestionError = '載入建議時發生錯誤: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSuggestions = false);
        Navigator.pop(context); // 關閉 Loading Dialog
        _showSuggestionsDialog(); // 開啟顯示結果或錯誤的 Dialog
      }
    }
  }

  // --- 輔助函式：搜尋新聞 ---
  Future<List<String>> _fetchNews(String companyName, String? jobTitle) async {
    List<String> snippets = [];
    try {
      print('正在搜尋關於 $companyName ($jobTitle) 的新聞...');

      // 建立動態的搜尋查詢列表
      List<String> queries = ["\"$companyName\" 產業動態", "\"$companyName\" 最近新聞"];

      // 如果有職稱，加入職稱相關的搜尋
      if (jobTitle != null && jobTitle.isNotEmpty) {
        queries.add("\"$jobTitle\" 產業趨勢");
        queries.add("\"$jobTitle\" 最新消息");
      }

      // 使用修正後的呼叫方式 (位置參數)
      final searchResults = await _googleSearchService.search(queries);

      // 解析 searchResults (List<Map<String, String>>)
      if (searchResults.isNotEmpty) {
        for (var item in searchResults) {
          String title = item['title'] ?? '';
          String snippet = item['snippet'] ?? '';
          String combined = title.isNotEmpty ? "$title：$snippet" : snippet;

          if (combined.isNotEmpty) {
            snippets.add(
              combined.length > 100
                  ? '${combined.substring(0, 100)}...'
                  : combined,
            );
          }
        }
      }
      print('新聞摘要: $snippets');
    } catch (e) {
      debugPrint("Error fetching news from Google Search: $e");
    }
    return snippets;
  }

  // --- 輔助函式：顯示建議的 Dialog (Modal Bottom Sheet) ---
  void _showSuggestionsDialog() {
    showModalBottomSheet(
      context: context,
      isDismissible: !_isLoadingSuggestions, // 載入中不可關閉
      enableDrag: !_isLoadingSuggestions,
      builder: (context) {
        Widget content;
        if (_isLoadingSuggestions) {
          content = const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在為您產生對話建議...'),
                ],
              ),
            ),
          );
        } else if (_suggestionError != null) {
          content = Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Text('錯誤: $_suggestionError'),
            ),
          );
        } else if (_dialogSuggestions.isEmpty) {
          content = const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text('目前沒有對話建議'),
            ),
          );
        } else {
          // 成功取得建議
          content = ListView(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
                child: Text(
                  '試試看這樣開場：',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ..._dialogSuggestions.map(
                (suggestion) => ListTile(
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Icon(
                      Icons.lightbulb_outline,
                      color: Colors.amber,
                      size: 28,
                    ),
                  ),
                  title: Text(suggestion),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.all(16.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: content,
          ),
        );
      },
    );
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
    final dir = await getTemporaryDirectory(); // 改這裡
    final filename = "conv_${DateTime.now().millisecondsSinceEpoch}.wav";
    return "${dir.path}/$filename";
  }


  //  查找 contact_id
  Future<int?> _resolveContactIdForUser(int friendUserId) async {
    final myId = _supabaseService.myUserId;

    final rows = await Supabase.instance.client
        .from('contacts')
        .select('contact_id')
        .or(
          'and(requester_id.eq.$myId,friend_id.eq.$friendUserId),'
          'and(requester_id.eq.$friendUserId,friend_id.eq.$myId)',
        )
        .eq('status', 'accepted')
        .limit(1);

    if (rows is List && rows.isNotEmpty) {
      return rows.first['contact_id'] as int;
    }
    return null;
  }


  
  // 🔹 2. 錄音函式（替代 _toggleRecording）
  // 傳入 friendUserId，根據名片上的使用者執行錄音、轉文字與寫入
  Future<void> _toggleRecordingFor(int friendUserId) async {
    try {
      if (!_isRecording) {
        // ====== 開始錄音 ======
        if (!await _recorder.hasPermission()) {
          _showSnackBar("沒有錄音權限");
          return;
        }

        final path = await _genWavPath();
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
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
        setState(() => _isRecording = false);
        if (p == null) {
          _showSnackBar("未取得錄音檔");
          return;
        }
        _recordPath = p;
        await Future.delayed(const Duration(milliseconds: 200));

        final f = File(_recordPath!);
        final exists = await f.exists();
        final len = exists ? await f.length() : 0;
        debugPrint('STT filePath=$_recordPath exists=$exists len=$len');
        if (!exists || len < 44) {
          _showSnackBar("錄音檔異常");
          return;
        }

        // ====== 取得 contact_id ======
        final contactId = await _resolveContactIdForUser(friendUserId);
        if (contactId == null) {
          _showSnackBar("尚未與此用戶建立聯絡人關係，無法儲存對話。");
          return;
        }

        // ====== STT（Whisper） ======
        String transcript = '';
        try {
          final stt = await _withTimeout(
            _stt.transcribeFile(_recordPath!, durationSec: DateTime.now().difference(_recordStartedAt!).inSeconds),
            const Duration(seconds: 180),
            'STT',
          );
          transcript = stt.text;
          debugPrint("STT: transcript.length=${transcript.length}");
        } catch (e) {
          debugPrint("STT: 轉文字失敗：$e");
          transcript = '（STT 失敗或逾時：$e）';
        }

        // ====== 摘要 ======
        String? summary;
        try {
          summary = await _summaryService.summarize(transcript);
          debugPrint("AI summary: ${summary?.length ?? 0} chars");
        } catch (e) {
          debugPrint("AI 摘要失敗：$e");
        }

        // ====== upsert：覆蓋最後一筆 ======
        try {
          final id = await _upsertConversationRecordByContact(
            contactId: contactId,
            content: transcript.isEmpty ? '（無內容）' : transcript,
            summary: summary,
            eventName: "對話錄音",
            audioDurationSec: DateTime.now().difference(_recordStartedAt!).inSeconds,
          );
          _showSnackBar("DB 已更新（record_id=$id）");
        } catch (e, st) {
          debugPrint("DB upsert failed: $e\n$st");
          _showSnackBar("寫入資料庫失敗");
        }

        // （可選）確認
        await _debugFetchLatestRecord();
      }
    } catch (e) {
      _showSnackBar("錄音流程錯誤：$e");
      setState(() => _isRecording = false);
    }
  }


  Future<void> _openConversationReview(int friendUserId) async {
    try {
      final myId = _supabaseService.myUserId;

      // 1) 找我們兩人的 contact_id（任一方向）
      final contacts = await Supabase.instance.client
          .from('contacts')
          .select('contact_id, requester_id, friend_id, status')
          .or(
            'and(requester_id.eq.$myId,friend_id.eq.$friendUserId),and(requester_id.eq.$friendUserId,friend_id.eq.$myId)',
          )
          .eq('status', 'accepted') // 只看已接受的關係
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
                    onRecordPressed: () => _openConversationReview(profile.userId),
                    onChatPressed: () => _fetchDialogSuggestions(profile),
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
                  onPressed: () async {
                    if (_nearbyFriendIds.isEmpty) {
                      _showSnackBar("附近沒有偵測到好友，無法開始錄音。");
                      return;
                    }
                    final friendId = _nearbyFriendIds.first;
                    await _toggleRecordingFor(friendId);
                  },
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
