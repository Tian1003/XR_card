// lib/features/exchange/card_exchange_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/core/widgets/business_card.dart';

class CardExchangePage extends StatefulWidget {
  const CardExchangePage({
    super.key,
    required this.peerUserId,
  });

  final int peerUserId;

  @override
  State<CardExchangePage> createState() => _CardExchangePageState();
}

class _CardExchangePageState extends State<CardExchangePage> {
  late final SupabaseService _svc;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _svc = SupabaseService(Supabase.instance.client);
  }

  Future<UserCompleteProfile?> _load() {
    return _svc.fetchUserCompleteProfile(widget.peerUserId);
  }

  Future<void> _onAccept() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      // 雙方同時停在交換頁時，任一方按接受即可建立 / 更新 contacts 為 accepted
      await _svc.acceptContact(me: _svc.myUserId, peer: widget.peerUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已接受並新增到聯絡人')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接受失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onDecline() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _svc.declineContact(me: _svc.myUserId, peer: widget.peerUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拒絕')),
      );
      Navigator.of(context).pop(false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拒絕失敗：$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface, // 與 profile_page 同系底色（避免自定 AppColors）
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: theme.textTheme.bodyMedium?.color,
        elevation: 0,
        title: const Text('交換名片'),
      ),
      body: FutureBuilder<UserCompleteProfile?>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('讀取失敗：${snap.error}'));
          }
          final p = snap.data;
          if (p == null) {
            return const Center(child: Text('找不到此使用者'));
          }

          // 內容區 — 盡量貼近 profile_page 的卡片式風格
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 名片視覺（沿用你專案的 BusinessCard widget，樣式風格跟 profile_page 一致）
                Card(
                  color: cs.surfaceVariant,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: BusinessCard(profile: p),
                  ),
                ),

                const SizedBox(height: 16),

                // 基本資訊（與 profile_page 類似的 info 區塊）
                Card(
                  color: cs.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow(
                          context,
                          icon: Icons.badge_outlined,
                          label: '職稱',
                          value: p.jobTitle ?? '-',
                        ),
                        const SizedBox(height: 10),
                        _infoRow(
                          context,
                          icon: Icons.apartment_outlined,
                          label: '公司',
                          value: p.company ?? '-',
                        ),
                        const SizedBox(height: 10),
                        _infoRow(
                          context,
                          icon: Icons.mail_outline,
                          label: 'Email',
                          value: p.email ?? '-',
                        ),
                        const SizedBox(height: 10),
                        _infoRow(
                          context,
                          icon: Icons.phone_iphone_outlined,
                          label: '電話',
                          value: p.phone ?? '-',
                        ),
                        if (p.socialLinks.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Divider(color: cs.outlineVariant, height: 1),
                          const SizedBox(height: 14),
                          Text(
                            '社群連結',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: p.socialLinks.map((s) {
                              return Chip(
                                label: Text(s.displayName ?? s.platform),
                                backgroundColor: cs.surfaceVariant,
                                side: BorderSide(color: cs.outlineVariant),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),

      // 底部「拒絕 / 接受」按鈕（替換原本 Edit / Preview）
      bottomNavigationBar: SafeArea(
        child: Container(
          color: cs.surface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : _onDecline,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.outline),
                    foregroundColor: theme.textTheme.bodyMedium?.color,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('拒絕'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _onAccept,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('接受'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textColor = theme.textTheme.bodyMedium?.color;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: cs.onSurface.withOpacity(0.6)),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
              children: [
                TextSpan(
                  text: '$label  ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
                ),
                TextSpan(
                  text: value,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
