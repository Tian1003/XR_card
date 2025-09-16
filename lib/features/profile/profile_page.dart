import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/core/widgets/business_card.dart';
import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/data/supabase_services.dart';

import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _svc = SupabaseService(Supabase.instance.client);
  UserCompleteProfile? _userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _svc.fetchUserCompleteProfile();
      setState(() {
        _userData = data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('load profile error: $e');
    }
  }

  Future<void> _goEdit() async {
    if (_userData == null) return;

    final updated = await Navigator.push<UserCompleteProfile>(
      context,
      MaterialPageRoute(builder: (_) => EditProfilePage(profile: _userData!)),
    );

    // mounted: Flutter State 的屬性。避免在已被銷毀的 widget 上呼叫 setState
    if (!mounted) return;

    if (updated != null) {
      // 用回傳快照立即更新
      setState(() => _userData = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_userData != null) ...[
                BusinessCard(profile: _userData!),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    BuildButton(
                      text: 'Edit',
                      isSelected: false,
                      onPressed: _goEdit,
                    ),
                    BuildButton(
                      text: 'Preview',
                      isSelected: false,
                      onPressed: () {
                        debugPrint('Preview 按下去了');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
