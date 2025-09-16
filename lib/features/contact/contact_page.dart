import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/data/supabase_services.dart';
import 'package:my_app/data/models/contact_relationships.dart';

import 'contact_detail_page.dart'; // 引入詳情頁面

class ContactPage extends StatefulWidget {
  final int? userId; // 可選，若不傳則用 currentUserId: 1
  const ContactPage({super.key, this.userId});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final SupabaseService _supabaseService = SupabaseService(
    Supabase.instance.client,
  );
  List<ContactRelationship> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await _supabaseService.fetchAcceptedContacts();
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading contacts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Contact',
          style: TextStyle(
            color: AppColors.primary, // 自訂顏色
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.primary, height: 3),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
          ? const Center(child: Text('沒有聯絡人'))
          : ListView.separated(
              itemCount: _contacts.length,
              separatorBuilder: (context, index) => const Divider(height: 2),
              padding: const EdgeInsets.symmetric(horizontal: 15), // 水平 padding
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final contactDisplay = _asDisplay(
                  widget.userId ?? SupabaseService.currentUserId,
                  contact,
                );

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(
                      contactDisplay.avatar != '' ? contactDisplay.avatar : '',
                    ),
                    radius: 24,
                  ),
                  title: Text(
                    contactDisplay.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text(
                    contactDisplay.subtitle,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  // 添加點擊事件
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactDetailPage(
                          contactId: contactDisplay.contactPersonId,
                        ),
                      ),
                    );
                  },
                  // 添加尾部箭頭圖標
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: AppColors.primary,
                    size: 16,
                  ),
                );
              },
            ),
    );
  }

  /// 將 model 轉成 UI 需要的顯示資料
  _ContactDisplay _asDisplay(int me, ContactRelationship c) {
    final meIsRequester = c.requesterId == me;

    final contactUserName = meIsRequester
        ? c.friendUsername
        : c.requesterUsername;

    // final contactNickname = meIsRequester
    //     ? c.requesterSetNickname
    //     : c.friendSetNickname;

    // 設定名稱，是否有暱稱？
    // final displayName = (contactNickname != null && contactNickname.trim().isNotEmpty)
    //     ? contactNickname
    //     : (contactUserName.isNotEmpty ? contactUserName : '未命名');
    final displayName = contactUserName; // 先不用暱稱

    final avatar = meIsRequester ? c.friendAvatar : c.requesterAvatar;
    final title = meIsRequester ? c.friendJobTitle : c.requesterJobTitle;
    final company = meIsRequester ? c.friendCompany : c.requesterCompany;

    final subtitle = [
      if (company != null && company.isNotEmpty) company,
      if (title != null && title.isNotEmpty) title,
    ].join(' | ');

    return _ContactDisplay(
      contactId: c.contactId,
      contactPersonId: meIsRequester ? c.friendId : c.requesterId,
      displayName: displayName,
      subtitle: subtitle,
      avatar: avatar ?? '',
    );
  }
}

class _ContactDisplay {
  final int contactId;
  final int contactPersonId;
  final String displayName;
  final String subtitle;
  final String avatar;
  _ContactDisplay({
    required this.contactId,
    required this.contactPersonId,
    required this.displayName,
    required this.subtitle,
    required this.avatar,
  });
}
