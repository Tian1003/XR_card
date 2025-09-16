import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/user_complete_profile.dart';
import 'models/contact_relationships.dart';

class SupabaseService {
  final SupabaseClient _client;
  static const int currentUserId = 1; // 這裡固定你要的 1 號使用者
  SupabaseService(this._client);

  /// 讀取 1 號（或指定）使用者的完整資料（含社群連結 JSON）
  Future<UserCompleteProfile?> fetchUserCompleteProfile([int? userId]) async {
    final id = userId ?? currentUserId;
    final data = await _client
        .from('user_complete_profile')
        .select('*')
        .eq('user_id', id)
        .maybeSingle();

    if (data == null) return null;
    return UserCompleteProfile.fromJson(data);
  }

  /// 更新 users 表（只會更新你傳入的欄位）
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

  /// social_links: 同步用戶的社群連結（期望清單）到 Supabase
  /// 1. 讀出目前 DB 的資料（這裡把必要欄位都取回來）
  /// 2. 比對期望清單與目前 DB 資料，分別決定要：
  ///    - 刪除：DB 有但期望清單沒有的平臺
  ///    - 新增：期望清單有、DB 沒有的平臺
  ///    - 更新：兩邊都有，但內容不同的平臺
  Future<void> syncSocialLinks({
    required int userId,
    required List<SocialLink> desired,
  }) async {
    // 讀出目前 DB 的資料（這裡把必要欄位都取回來）
    final rows =
        await _client
                .from('social_links')
                .select(
                  'link_id, platform, url, display_name, display_order, is_active',
                )
                .eq('user_id', userId)
            as List;

    // 1) 轉成以 platform（小寫）為 key 的 map，方便比對
    Map<String, Map<String, dynamic>> dbByPlatform = {
      for (final r in rows)
        (r['platform'] as String).toLowerCase(): r as Map<String, dynamic>,
    };

    Map<String, SocialLink> desiredByPlatform = {
      for (final l in desired) l.platform.toLowerCase(): l,
    };

    // 2) 刪除：DB 有但期望清單沒有的平臺
    final toDeleteIds = <int>[];
    for (final p in dbByPlatform.keys) {
      if (!desiredByPlatform.containsKey(p)) {
        final id = dbByPlatform[p]!['link_id'] as int;
        toDeleteIds.add(id);
      }
    }
    if (toDeleteIds.isNotEmpty) {
      await _client
          .from('social_links')
          .delete()
          .inFilter('link_id', toDeleteIds);
    }

    // 3) 新增：期望清單有、DB 沒有的平臺
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

    // 4) 更新：兩邊都有，但內容不同的平臺
    //    逐筆比較：url / display_name / display_order / is_active
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

  /// 讀取 1 號（或指定）使用者所有「已接受」的聯絡人，並整理成清單可直接給 ListTile 用
  Future<List<ContactRelationship>> fetchAcceptedContacts([int? userId]) async {
    final id = userId ?? currentUserId;

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

  // /// 新增使用者（示例；正式建議走 Auth 或 Edge Function）
  // Future<int> insertUser(Map<String, dynamic> data) async {
  //   final inserted = await _client
  //       .from('users')
  //       .insert(data)
  //       .select('user_id')
  //       .single();
  //   return inserted['user_id'] as int;
  // }

  // /// 新增/更新多筆社群連結
  // Future<void> upsertSocialLinks(
  //   int userId,
  //   List<Map<String, dynamic>> links,
  // ) async {
  //   final payload = links.map((m) => {'user_id': userId, ...m}).toList();
  //   await _client.from('social_links').upsert(payload);
  // }

  // /// 新增/更新我對某聯絡人的個人化設定（暱稱、備註、標籤）
  // Future<void> upsertContactProfile({
  //   required int contactId,
  //   int? ownerId,
  //   String? nickname,
  //   String? note,
  //   List<String>? tags,
  // }) async {
  //   final id = ownerId ?? currentUserId;
  //   await _client.from('contact_profiles').upsert({
  //     'contact_id': contactId,
  //     'owner_id': id,
  //     if (nickname != null) 'nickname': nickname,
  //     if (note != null) 'note': note,
  //     if (tags != null) 'tags': tags,
  //   });
  // }
}
