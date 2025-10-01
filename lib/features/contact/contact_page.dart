// lib/features/contact/contact_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/data/models/contact_relationships.dart';
import 'package:my_app/data/models/user_complete_profile.dart';

import 'contact_detail_page.dart';

class ContactPage extends StatefulWidget {
  final int? userId;
  const ContactPage({super.key, this.userId});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  late final SupabaseService _svc;
  late final int _me;

  bool _loading = true;
  List<ContactRelationship> _accepted = const [];
  List<UserCompleteProfile> _profiles = const [];

  @override
  void initState() {
    super.initState();
    _svc = SupabaseService(Supabase.instance.client);
    _me = widget.userId ?? SupabaseService.currentUserId;
    _refresh(); // 首次進頁面自動抓一次
  }

  Future<void> _refresh() async {
    try {
      setState(() => _loading = true);

      // 1) 取 accepted 關係
      final rows = await _svc.fetchAcceptedContacts(_me);

      // 2) 轉出「對方 userId」
      final peerIds = <int>[
        for (final r in rows) r.requesterId == _me ? r.friendId : r.requesterId,
      ];

      // 3) 取對方們的名片資料
      final profiles = await _svc.fetchProfilesByIds(peerIds);

      // 4) 依照 updated_at 將 profiles 排序（與 rows 對齊的感覺）
      final order = {
        for (int i = 0; i < rows.length; i++)
          (rows[i].requesterId == _me ? rows[i].friendId : rows[i].requesterId): i
      };
      profiles.sort((a, b) => (order[a.userId] ?? 1 << 30).compareTo(order[b.userId] ?? 1 << 30));

      setState(() {
        _accepted = rows;
        _profiles = profiles;
      });
    } catch (e) {
      debugPrint('Contact refresh error: $e');
      // 可以視需要 showSnackBar
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleBar = AppBar(
      centerTitle: false,
      backgroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Contact',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: ColoredBox(color: AppColors.primary, child: SizedBox(height: 3)),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.primary),
          onPressed: _refresh,
          tooltip: '重新整理',
        ),
      ],
    );

    // 空清單也要能下拉，所以用 RefreshIndicator 包住 AlwaysScrollable 的 ListView
    Widget list;
    if (_loading && _profiles.isEmpty) {
      list = const Center(child: CircularProgressIndicator());
    } else if (_profiles.isEmpty) {
      list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('沒有聯絡人')),
          SizedBox(height: 400), // 讓頁面可拉
        ],
      );
    } else {
      list = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _profiles.length,
        separatorBuilder: (_, __) => const Divider(height: 2),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemBuilder: (context, index) {
          final profile = _profiles[index];
          final displayName = profile.username;
          final subtitle = [
            if ((profile.company ?? '').isNotEmpty) profile.company!,
            if ((profile.jobTitle ?? '').isNotEmpty) profile.jobTitle!,
          ].join(' | ');

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            leading: CircleAvatar(
              radius: 24,
              backgroundImage: (profile.avatarUrl ?? '').isNotEmpty
                  ? NetworkImage(profile.avatarUrl!)
                  : null,
              child: (profile.avatarUrl ?? '').isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            trailing: const Icon(Icons.arrow_forward_ios, color: AppColors.primary, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContactDetailPage(contactId: profile.userId),
                ),
              );
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: titleBar,
      body: RefreshIndicator(
        onRefresh: _refresh,
        displacement: 36, // 下拉圈圈的位置
        child: list,
      ),
    );
  }
}
