// lib/services/relationship_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 用 contact_relationships 當「協商＋結果」的唯一資料表：
/// - A 點 B：insert 一筆 (requester=A, friend=B, status='pending')
/// - B 端：透過 Realtime 監聽 friend=B 的 insert，看到 pending → 彈窗 → 接受後把同一筆改為 'accepted'
/// - A 端：監聽自己發出去那筆（requester=A）的 update；狀態變 'accepted' → 導頁
class RelationshipService {
  RelationshipService._();
  static final RelationshipService I = RelationshipService._();
  final _sp = Supabase.instance.client;

  RealtimeChannel? _incoming; // 監看「我被邀請」的 pending（friend_id == me）
  final Map<String, RealtimeChannel> _outgoingChans = {}; // 以對方 userId 區分

  /// 訂閱入站 pending：有別人把我放在 friend_id 的新紀錄就會回呼
  Future<void> subscribeForIncomingPending(
    Future<bool> Function(Map row) onAskUserToAccept, // 回傳 true 表接受
    void Function(Map acceptedRow)? onAcceptedNavigate, // 接受後導頁
  ) async {
    final me = _sp.auth.currentUser?.id;
    if (me == null) return;

    await _incoming?.unsubscribe();
    _incoming = _sp.channel('rel-in-$me')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'contact_relationships',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'friend_id',
          value: me,
        ),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row['status'] == 'pending') {
            final ok = await onAskUserToAccept(row);
            if (ok) {
              await acceptPending(requesterId: row['requester_id']);
              // 查回最新狀態（避免 race）
              final updated = await _latestPairRow(
                a: row['requester_id'], b: me,
              );
              if (updated != null && onAcceptedNavigate != null) {
                onAcceptedNavigate(updated);
              }
            }
          }
        },
      )
      ..subscribe();
  }

  /// 我 → 對方：建立 pending
  Future<Map<String, dynamic>> createPending({required String otherUserId}) async {
    final me = _sp.auth.currentUser!.id;
    // 先查是否已存在一筆 A↔B（避免多筆）
    final existing = await _getAnyPairRow(a: me, b: otherUserId);
    if (existing != null) {
      // 若已是 accepted 就直接回它；否則把它更新到 pending（刷新時間）
      if (existing['status'] != 'pending') {
        await _sp.from('contact_relationships').update({
          'status': 'pending',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('contact_id', existing['contact_id']);
      }
      return await _getRowById(existing['contact_id']) ?? existing;
    }

    final row = await _sp.from('contact_relationships').insert({
      'requester_id': me,
      'friend_id': otherUserId,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).select().single();

    return row;
  }

  /// 我是被邀者（friend=我），點「接受」
  Future<void> acceptPending({required String requesterId}) async {
    final me = _sp.auth.currentUser!.id;
    await _sp.from('contact_relationships').update({
      'status': 'accepted',
      'updated_at': DateTime.now().toIso8601String(),
    })
    .eq('requester_id', requesterId)
    .eq('friend_id', me)
    .eq('status', 'pending');
  }

  /// 監看我發出去的那筆是否被接受（狀態變 accepted）
  Future<void> watchMyOutgoing({
    required String otherUserId,
    required void Function(Map row) onAccepted,
  }) async {
    final me = _sp.auth.currentUser!.id;
    final key = otherUserId;
    // 先關掉舊的
    if (_outgoingChans[key] != null) {
      await _outgoingChans[key]!.unsubscribe();
      _outgoingChans.remove(key);
    }

    final ch = _sp.channel('rel-out-$me-$otherUserId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'contact_relationships',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'requester_id',
          value: me,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          // 再次檢查「同一對 pair」＆狀態
          if (row['friend_id'] == otherUserId && row['status'] == 'accepted') {
            onAccepted(row);
          }
        },
      )
      ..subscribe();

    _outgoingChans[key] = ch;
  }

  Future<void> unsubscribeAll() async {
    await _incoming?.unsubscribe();
    for (final ch in _outgoingChans.values) {
      await ch.unsubscribe();
    }
    _outgoingChans.clear();
  }

  // —— 私有小工具 —— //

  Future<Map<String, dynamic>?> _getAnyPairRow({
    required String a, required String b,
  }) async {
    final rows = await _sp.from('contact_relationships')
        .select()
        .or('and(requester_id.eq.$a,friend_id.eq.$b),and(requester_id.eq.$b,friend_id.eq.$a)')
        .order('updated_at', ascending: false)
        .limit(1);
    if (rows is List && rows.isNotEmpty) return rows.first as Map<String, dynamic>;
    return null;
  }

  Future<Map<String, dynamic>?> _latestPairRow({
    required String a, required String b,
  }) async {
    return await _getAnyPairRow(a: a, b: b);
  }

  Future<Map<String, dynamic>?> _getRowById(dynamic contactId) async {
    try {
      return await _sp.from('contact_relationships')
          .select().eq('contact_id', contactId).single();
    } catch (_) {
      return null;
    }
  }
}
