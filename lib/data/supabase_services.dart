// lib/data/supabase_services.dart
import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/user_complete_profile.dart';
import 'models/contact_relationships.dart';

class SupabaseService {
  final SupabaseClient _client;

  /// 真正使用的目前使用者 ID（iPad=1、iPhone=2）
  final int _currentUserId;
  int get myUserId => _currentUserId;

  static SupabaseService? _instance;

  SupabaseService._(this._client, this._currentUserId);

  /// 建議在 main()：await SupabaseService.init(Supabase.instance.client);
  static Future<void> init(SupabaseClient client) async {
    final id = await _detectUserIdByDevice();
    _instance = SupabaseService._(client, id);
  }

  /// 相容你現有用法：SupabaseService(Supabase.instance.client)
  factory SupabaseService(SupabaseClient client) {
    _instance ??= SupabaseService._(client, 2); // 預設當作手機: 2
    return _instance!;
  }

  /// 舊寫法相容：提供靜態 currentUserId
  static int get currentUserId => _instance?._currentUserId ?? 2;

  // iPad=1 / 其餘=2
  static Future<int> _detectUserIdByDevice() async {
    try {
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        final model = (info.model ?? '').toLowerCase();
        final name = (info.name ?? '').toLowerCase();
        final machine = (info.utsname.machine ?? '').toLowerCase();
        final isIpad =
            model.contains('ipad') ||
            name.contains('ipad') ||
            machine.startsWith('ipad');
        return isIpad ? 1 : 2;
      }
    } catch (_) {}
    return 2;
  }

  /// 上傳頭像圖片到 Storage
  ///
  /// @param imageFile 使用者選擇的圖片檔案
  /// @param userId 使用者 ID，用來建立獨特的檔案路徑
  /// @return 上傳成功後的公開 URL，若失敗則回傳 null
  Future<String?> uploadAvatarToStorage(File imageFile, int userId) async {
    try {
      final fileExt = imageFile.path.split('.').last;
      // 使用 user ID 和時間戳建立一個獨一無二的檔案名稱，避免衝突
      final fileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = fileName;

      // 上傳到 'avatars' bucket
      await _client.storage
          .from('avatars')
          .upload(
            filePath,
            imageFile,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      // 取得上傳後的公開 URL
      final imageUrl = _client.storage.from('avatars').getPublicUrl(filePath);
      return imageUrl;
    } catch (e) {
      // 在 release 模式下，建議使用更完善的日誌系統
      debugPrint('SupabaseService::uploadAvatarToStorage Error: $e');
      return null;
    }
  }

  // ---------------------------
  // Users / Profiles
  // ---------------------------

  Future<UserCompleteProfile?> fetchUserCompleteProfile([int? userId]) async {
    final id = userId ?? _currentUserId;
    final data = await _client
        .from('user_complete_profile')
        .select('*')
        .eq('user_id', id)
        .maybeSingle();
    if (data == null) return null;
    return UserCompleteProfile.fromJson(data);
  }

  /// 一次拿多人的完整名片（from view: user_complete_profile）
  Future<List<UserCompleteProfile>> fetchProfilesByIds(
    Iterable<int> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return <UserCompleteProfile>[];

    final rows =
        await _client
                .from('user_complete_profile')
                .select('*')
                .inFilter('user_id', idList)
            as List;

    return rows
        .map((m) => UserCompleteProfile.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateUser({
    required int userId,
    String? avatarUrl,
    String? username,
    String? company,
    String? jobTitle,
    String? skill,
    String? email,
    String? phone,
    String? qrCodeUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (username != null) updates['username'] = username;
    if (company != null) updates['company'] = company;
    if (jobTitle != null) updates['job_title'] = jobTitle;
    if (skill != null) updates['skill'] = skill;
    if (email != null) updates['email'] = email;
    if (phone != null) updates['phone'] = phone;
    if (qrCodeUrl != null) updates['qr_code_url'] = qrCodeUrl;
    if (updates.isEmpty) return;
    await _client.from('users').update(updates).eq('user_id', userId);
  }

  Future<void> syncSocialLinks({
    required int userId,
    required List<SocialLink> desired,
  }) async {
    final rows =
        await _client
                .from('social_links')
                .select(
                  'link_id, platform, url, display_name, display_order, is_active',
                )
                .eq('user_id', userId)
            as List;

    final dbByPlatform = <String, Map<String, dynamic>>{
      for (final r in rows)
        (r['platform'] as String).toLowerCase(): r as Map<String, dynamic>,
    };
    final desiredByPlatform = <String, SocialLink>{
      for (final l in desired) l.platform.toLowerCase(): l,
    };

    final toDeleteIds = <int>[
      for (final p in dbByPlatform.keys)
        if (!desiredByPlatform.containsKey(p))
          dbByPlatform[p]!['link_id'] as int,
    ];
    if (toDeleteIds.isNotEmpty) {
      await _client
          .from('social_links')
          .delete()
          .inFilter('link_id', toDeleteIds);
    }

    final toInsert = <Map<String, dynamic>>[];
    for (final entry in desiredByPlatform.entries) {
      final p = entry.key;
      final l = entry.value;
      if (!dbByPlatform.containsKey(p)) {
        toInsert.add({
          'user_id': userId,
          'platform': l.platform,
          'url': l.url,
          'display_name': l.displayName,
          'display_order': l.displayOrder,
          'is_active': l.isActive,
        });
      }
    }
    if (toInsert.isNotEmpty) {
      await _client.from('social_links').insert(toInsert);
    }

    for (final entry in desiredByPlatform.entries) {
      final p = entry.key;
      final l = entry.value;
      if (!dbByPlatform.containsKey(p)) continue;

      final db = dbByPlatform[p]!;
      final current = (
        url: (db['url'] ?? '') as String,
        name: db['display_name'] as String?,
        order: (db['display_order'] ?? 0) as int,
        active: (db['is_active'] ?? false) as bool,
      );
      final next = (
        url: l.url,
        name: l.displayName,
        order: l.displayOrder,
        active: l.isActive,
      );

      final isDifferent =
          current.url != next.url ||
          (current.name ?? '') != (next.name ?? '') ||
          current.order != next.order ||
          current.active != next.active;

      if (isDifferent) {
        await _client
            .from('social_links')
            .update({
              'url': next.url,
              'display_name': next.name,
              'display_order': next.order,
              'is_active': next.active,
            })
            .eq('link_id', db['link_id']);
      }
    }
  }

  // ---------------------------
  // Contacts（不改你的資料表）
  // ---------------------------

  /// 即時監聽 + 輪詢備援：任何與我有關的關係變動（insert/update/delete）→ 回傳最新的 contact_relationships
  Stream<List<ContactRelationship>> contactsStream({required int me}) {
    final controller = StreamController<List<ContactRelationship>>.broadcast();
    Timer? _poll;
    RealtimeChannel? _channel;

    Future<void> _emit() async {
      try {
        final rows =
            await _client
                    .from('contact_relationships')
                    .select()
                    .or('requester_id.eq.$me,friend_id.eq.$me')
                    .order('updated_at', ascending: false)
                as List;

        final list = rows
            .map((m) => ContactRelationship.fromJson(m as Map<String, dynamic>))
            .toList();

        if (!controller.isClosed) controller.add(list);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    // 初始推一次
    _emit();

    // Realtime 訂閱 contacts（只要有變更且跟我有關，就重抓一次）
    _channel = _client
        .channel('public:contacts_stream_user_$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'contacts',
          callback: (payload) {
            bool involvesMe(Map<String, dynamic>? row) {
              if (row == null) return false;
              final req = (row['requester_id'] as num?)?.toInt();
              final fri = (row['friend_id'] as num?)?.toInt();
              return req == me || fri == me;
            }

            if (involvesMe(payload.newRecord) ||
                involvesMe(payload.oldRecord)) {
              _emit();
            }
          },
        )
        .subscribe();

    // 備援輪詢（Realtime 偶爾漏事件或沒啟用時仍能更新）
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _emit());

    controller.onCancel = () async {
      _poll?.cancel();
      if (_channel != null) {
        await _client.removeChannel(_channel!);
      }
    };

    return controller.stream;
  }

  /// 取與我有關的 userId 清單（僅 accepted / 或含 pending）
  Future<Set<int>> fetchContactUserIds({
    required int me,
    bool includePending = true,
  }) async {
    final statuses = includePending ? ['accepted', 'pending'] : ['accepted'];

    final rows =
        await _client
                .from('contacts')
                .select('requester_id, friend_id, status')
                .or('requester_id.eq.$me,friend_id.eq.$me')
                .inFilter('status', statuses)
            as List;

    final ids = <int>{};
    for (final r in rows) {
      final a = (r['requester_id'] as num).toInt();
      final b = (r['friend_id'] as num).toInt();
      final other = a == me ? b : a;
      if (other != me) ids.add(other);
    }
    return ids;
  }

  /// （清單頁用）已接受的關係（若你有其他地方在用，保留這個 API）
  Future<List<ContactRelationship>> fetchAcceptedContacts([int? userId]) async {
    final id = userId ?? _currentUserId;
    final rows =
        await _client
                .from('contact_relationships')
                .select()
                .or('requester_id.eq.$id,friend_id.eq.$id')
                .eq('status', 'accepted')
                .order('updated_at', ascending: false)
            as List;

    return rows
        .map((m) => ContactRelationship.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------
  // 同意 / 拒絕（不改表結構）
  // ---------------------------

  /// 我按「接受」：
  /// 1) 先確保「我->對方」至少有一筆 pending（沒有就插入）
  /// 2) 嘗試把「對方->我」的 pending 升級為 accepted（只有雙方都按接受才會成功）
  /// 回傳：這次呼叫是否升級成功（true=已成為好友；false=目前仍是 pending）
  // lib/data/supabase_services.dart 內
  // lib/data/supabase_services.dart 內
  Future<bool> acceptContact({required int me, required int peer}) async {
    if (me == peer) return false;

    // 先找到這對關係（不分方向），最多一筆
    final List exist = await _client
        .from('contacts')
        .select('contact_id, requester_id, friend_id, status')
        .or(
          'and(requester_id.eq.$me,friend_id.eq.$peer),'
          'and(requester_id.eq.$peer,friend_id.eq.$me)',
        )
        .limit(1);

    if (exist.isEmpty) {
      // 完全沒有 → 我先送出 pending
      await _client.from('contacts').insert({
        'requester_id': me,
        'friend_id': peer,
        'status': 'pending',
      });
      return false; // 目前只是送出邀請
    }

    final row = exist.first as Map<String, dynamic>;
    final status = (row['status'] as String?) ?? 'pending';
    final req = (row['requester_id'] as num).toInt();
    final fri = (row['friend_id'] as num).toInt();

    if (status == 'accepted') {
      // 已是好友，直接成功（不要再 insert 以免撞唯一索引）
      return true;
    }

    if (status == 'pending') {
      if (req == peer && fri == me) {
        // 我是被邀請方 → 這次就把它升級為 accepted
        await _client
            .from('contacts')
            .update({
              'status': 'accepted',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('contact_id', row['contact_id']);
        return true;
      } else {
        // 我早就送過邀請了，現在只是再按一次接受 → 什麼都不做
        return false;
      }
    }

    // 其它狀態不處理
    return false;
  }

  /// 我按「拒絕」：刪除雙向 pending；若已 accepted 則不動
  Future<bool> declineContact({required int me, required int peer}) async {
    if (me == peer) return false;

    final deleted = await _client
        .from('contacts')
        .delete()
        .or(
          'and(requester_id.eq.$me,friend_id.eq.$peer),'
          'and(requester_id.eq.$peer,friend_id.eq.$me)',
        )
        .eq('status', 'pending')
        .select();

    return (deleted as List).isNotEmpty;
  }

  /// 根據 QR 碼 token 獲取用戶信息
  Future<UserCompleteProfile?> getUserByQRToken(String token) async {
    try {
      final response = await _client
          .from('user_complete_profile')
          .select()
          .eq('qr_code_url', token)
          .maybeSingle();

      if (response != null) {
        final userId = response['user_id'] as int;
        return await fetchUserCompleteProfile(userId);
      }
      return null;
    } catch (e) {
      print('獲取 QR 用戶錯誤: $e'); // 使用 print 而非 debugPrint
      return null;
    }
  }

  // ---------------------------
  // [!!! 新增功能 !!!]
  // ---------------------------

  /// [新增] 獲取指定聯絡人的最新一筆對話摘要
  ///
  /// @param contactId 正在互動的聯絡人 User ID
  /// @return 最新的 summary 文字，若無則回傳 null
  Future<String?> fetchLatestConversationSummary(int contactId) async {
    try {
      // 假設 'conversation_records' 表中有 'contact_id' (對方的 ID) 和 'user_id' (我方 ID)
      // 查詢條件：我方 ID 是 _currentUserId 且 聯絡人 ID 是 contactId
      final response = await _client
          .from('conversation_records')
          .select('summary')
          .eq('user_id', _currentUserId) // 篩選自己的紀錄
          .eq('contact_id', contactId) // 篩選這位聯絡人
          .order('created_at', ascending: false) // 依時間排序
          .limit(1) // 只取最新一筆
          .maybeSingle();

      if (response != null && response['summary'] != null) {
        return response['summary'] as String;
      }
      return null; // 沒有找到摘要
    } catch (e) {
      debugPrint('Error fetching latest conversation summary: $e');
      return null; // 發生錯誤
    }
  }
}
