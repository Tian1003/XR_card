import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
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

  static Future<SupabaseService> create(SupabaseClient client) async {
    final id = await _detectUserIdByDevice();
    return SupabaseService._(client, id);
  }

  /// 賦予 iPhone 裝置 userId=2、iPad 裝置 userId=1
  factory SupabaseService(SupabaseClient client) {
    _instance ??= SupabaseService._(client, 2); // 預設給 2
    return _instance!;
  }

  /// 舊寫法相容：提供靜態 currentUserId
  static int get currentUserId => _instance?._currentUserId ?? 2;

  /// 建議在 main() 啟動時呼叫一次，完成偵測並覆寫單例
  static Future<void> init(SupabaseClient client) async {
    final id = await _detectUserIdByDevice();
    _instance = SupabaseService._(client, id);
  }

  // iPad=1 //
  static Future<int> _detectUserIdByDevice() async {
    try {
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        final model = (info.model ?? '').toLowerCase();
        final name = (info.name ?? '').toLowerCase();
        final machine = (info.utsname.machine ?? '').toLowerCase(); 
        final isIpad = model.contains('ipad') || name.contains('ipad') || machine.startsWith('ipad');
        return isIpad ? 1 : 2;
      }
    } catch (_) {}
    return 2; // 其他平台或偵測失敗 → 當作手機
  }

  // ====== 以下保留你原有 API 不變 ======

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
    final rows = await _client
        .from('social_links')
        .select('link_id, platform, url, display_name, display_order, is_active')
        .eq('user_id', userId) as List;

    final dbByPlatform = <String, Map<String, dynamic>>{
      for (final r in rows) (r['platform'] as String).toLowerCase(): r as Map<String, dynamic>,
    };
    final desiredByPlatform = <String, SocialLink>{
      for (final l in desired) l.platform.toLowerCase(): l,
    };

    final toDeleteIds = <int>[
      for (final p in dbByPlatform.keys)
        if (!desiredByPlatform.containsKey(p)) dbByPlatform[p]!['link_id'] as int,
    ];
    if (toDeleteIds.isNotEmpty) {
      await _client.from('social_links').delete().inFilter('link_id', toDeleteIds);
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

  Future<List<ContactRelationship>> fetchAcceptedContacts([int? userId]) async {
      final id = userId ?? _currentUserId;
      final rows = await _client
          .from('contact_relationships')
          .select()
          .or('requester_id.eq.$id,friend_id.eq.$id')
          .eq('status', 'accepted')
          .order('updated_at', ascending: false) as List;

      return rows
          .map((m) => ContactRelationship.fromJson(m as Map<String, dynamic>))
          .toList();
    }
  // lib/data/supabase_services.dart 內的 class SupabaseService {...} 裡

Future<void> acceptContact({required int me, required int peer}) async {
  if (me == peer) return;

  // 1) 將任一方向的 pending -> accepted
  final List updatedRows = await _client
      .from('contacts')
      .update({
        'status': 'accepted',
        'updated_at': DateTime.now().toIso8601String(),
      })
      .or(
        'and(requester_id.eq.$me,friend_id.eq.$peer),'
        'and(requester_id.eq.$peer,friend_id.eq.$me)',
      )
      .eq('status', 'pending')
      .select(); // 不要 maybeSingle/single，拿 List

  if (updatedRows.isNotEmpty) {
    // 有成功把 pending 變成 accepted，就完成了
    return;
  }

  // 2) 檢查是否已經有 accepted（任一方向）
  final List existsAccepted = await _client
      .from('contacts')
      .select('contact_id')
      .or(
        'and(requester_id.eq.$me,friend_id.eq.$peer),'
        'and(requester_id.eq.$peer,friend_id.eq.$me)',
      )
      .eq('status', 'accepted')
      .limit(1);

  if (existsAccepted.isNotEmpty) return;

  // 3) 都沒有 -> 直接插一筆 accepted
  await _client.from('contacts').insert({
    'requester_id': me,
    'friend_id': peer,
    'status': 'accepted',
  });
}

Future<void> upsertPending({required int me, required int peer}) async {
  if (me == peer) return;

  // 查是否已有任一方向的關係
  final List exist = await _client
      .from('contacts')
      .select('contact_id, status, requester_id, friend_id')
      .or(
        'and(requester_id.eq.$me,friend_id.eq.$peer),'
        'and(requester_id.eq.$peer,friend_id.eq.$me)',
      )
      .limit(1);

  if (exist.isEmpty) {
    // 完全沒有 → 建一筆 pending（由我發出）
    await _client.from('contacts').insert({
      'requester_id': me,
      'friend_id': peer,
      'status': 'pending',
    });
    return;
  }

  
}

/// 取與我有關係的對象 userIds（accepted 以及可選 pending）



}

// lib/data/supabase_services.dart
// ... 你的 SupabaseService 既有內容

extension ContactsQuery on SupabaseService {
  /// 取與我有關係的對象 userIds（accepted 以及可選 pending）
  Future<Set<int>> fetchContactUserIds({required int me, bool includePending = true}) async {
    final statuses = includePending ? ['accepted', 'pending'] : ['accepted'];

    final rows = await _client
        .from('contacts')
        .select('requester_id, friend_id, status')
        .or('requester_id.eq.$me,friend_id.eq.$me')
        .inFilter('status', statuses) as List;

    final ids = <int>{};
    for (final r in rows) {
      final a = (r['requester_id'] as num).toInt();
      final b = (r['friend_id'] as num).toInt();
      final other = a == me ? b : a;
      if (other != me) ids.add(other);
    }
    return ids;
  }

  Future<void> declineContact({required int me, required int peer}) async {
  // 拒絕 = 把彼此之間的 pending 關係移除（雙向）
  await _client
      .from('contacts')
      .delete()
      .or('and(requester_id.eq.$me,friend_id.eq.$peer),and(requester_id.eq.$peer,friend_id.eq.$me)');
}

}


  
