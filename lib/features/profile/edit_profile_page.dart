import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/data/models/user_complete_profile.dart';
import 'package:my_app/data/supabase_services.dart';

class EditProfilePage extends StatefulWidget {
  final UserCompleteProfile profile;
  const EditProfilePage({super.key, required this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final SupabaseService _svc;

  late TextEditingController nameCtrl;
  late TextEditingController companyCtrl;
  late TextEditingController titleCtrl;
  late TextEditingController skillsCtrl;
  late TextEditingController emailCtrl;

  String? _localAvatarPath; // 若要上傳頭貼可用

  // 需求指定 6 種平台
  static const List<String> kPlatforms = [
    'facebook',
    'instagram',
    'linkedin',
    'twitter',
    'github',
    'website',
  ];

  late final Map<String, int> _linkId;
  late final Map<String, TextEditingController> _nameCtrls; // displayName
  late final Map<String, TextEditingController> _urlCtrls;
  late final Map<String, int> _order; // 顯示排序 (0 預留，後續可擴展)
  late final Map<String, bool> _active;

  @override
  void initState() {
    super.initState();
    _svc = SupabaseService(Supabase.instance.client);

    // User Profile 初始化控制器
    nameCtrl = TextEditingController(text: widget.profile.username);
    companyCtrl = TextEditingController(text: widget.profile.company ?? '');
    titleCtrl = TextEditingController(text: widget.profile.jobTitle ?? '');
    skillsCtrl = TextEditingController(text: widget.profile.skill ?? '');
    emailCtrl = TextEditingController(text: widget.profile.email ?? '');

    // Social Links 初始化控制器
    _linkId = {for (final p in kPlatforms) p: 0};
    _nameCtrls = {for (final p in kPlatforms) p: TextEditingController()};
    _urlCtrls = {for (final p in kPlatforms) p: TextEditingController()};
    // _order = {for (var i = 0; i < kPlatforms.length; i++) kPlatforms[i]: i + 1};
    _order = {for (final p in kPlatforms) p: 0};
    _active = {for (final p in kPlatforms) p: false};

    // 把現有 profile.socialLinks 映射到控制器
    for (final l in widget.profile.socialLinks) {
      final p = l.platform.toLowerCase();
      if (_urlCtrls.containsKey(p)) {
        _linkId[p] = l.linkId;
        _nameCtrls[p]!.text = l.displayName ?? '';
        _urlCtrls[p]!.text = l.url;
        // _order[p] = l.displayOrder;
        _active[p] = l.isActive;
      }
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    companyCtrl.dispose();
    titleCtrl.dispose();
    skillsCtrl.dispose();
    emailCtrl.dispose();
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    for (final c in _urlCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (img != null) setState(() => _localAvatarPath = img.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // 顯示讀取中，避免重複點擊
    // (您可以加入一個 bool _isSaving 狀態來顯示 Loading 畫面)

    // 步驟 0: 如果有選擇新頭貼，先上傳
    String? avatarUrl = widget.profile.avatarUrl; // 先保留舊的 URL
    if (_localAvatarPath != null) {
      final uploadedUrl = await _svc.uploadAvatarToStorage(
        File(_localAvatarPath!),
        widget.profile.userId,
      );
      // 如果上傳成功，就使用新的 URL
      if (uploadedUrl != null) {
        avatarUrl = uploadedUrl;
      } else {
        // (可選) 上傳失敗時提醒使用者
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('頭像上傳失敗，請稍後再試')));
        }
        return; // 或者您可以選擇繼續儲存其他資料
      }
    }

    // 步驟 1: 更新 users 基本資料 (包含新的 avatarUrl)
    await _svc.updateUser(
      userId: widget.profile.userId,
      avatarUrl: avatarUrl,
      username: nameCtrl.text.trim(),
      company: companyCtrl.text.trim(),
      jobTitle: titleCtrl.text.trim(),
      skill: skillsCtrl.text.trim(),
      email: emailCtrl.text.trim(),
    );

    // 2) 蒐集 6 種平台 → 期望清單
    final managed = <SocialLink>[];
    for (final p in kPlatforms) {
      final id = _linkId[p] ?? 0;
      final name = _nameCtrls[p]!.text.trim();
      final url = _urlCtrls[p]!.text.trim();
      final ord = _order[p] ?? (kPlatforms.indexOf(p) + 1);
      final isActive = _active[p] ?? false;

      if (url.isNotEmpty) {
        managed.add(
          SocialLink(
            linkId: id,
            platform: p,
            displayName: name.isNotEmpty ? name : null,
            url: url,
            displayOrder: ord,
            isActive: isActive,
          ),
        );
      }
    }

    // 3) 其他平台保留: 暫時沒這個功能
    final others = widget.profile.socialLinks
        .where((l) => !kPlatforms.contains(l.platform.toLowerCase()))
        .toList();

    final desiredAll = [...managed, ...others];

    // 4) 同步 social_links（upsert + 刪除多餘）
    await _svc.syncSocialLinks(
      userId: widget.profile.userId,
      desired: desiredAll,
    );

    // 5) 組回更新後的本地 model，帶回上一頁立即更新
    final updated = widget.profile.copyWith(
      avatarUrl: avatarUrl, // ===== 修改處 =====
      username: nameCtrl.text.trim(),
      company: companyCtrl.text.trim(),
      jobTitle: titleCtrl.text.trim(),
      skill: skillsCtrl.text.trim(),
      email: emailCtrl.text.trim(),
      socialLinks: desiredAll,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('個人資料已儲存')));
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.primary,
            size: 28,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.primary, height: 3),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: (_localAvatarPath != null)
                      ? FileImage(File(_localAvatarPath!))
                      : (widget.profile.avatarUrl?.isNotEmpty == true)
                      ? NetworkImage(widget.profile.avatarUrl!)
                      : null,
                  child:
                      (_localAvatarPath == null &&
                          (widget.profile.avatarUrl?.isEmpty ?? true))
                      ? const Icon(
                          Icons.camera_alt,
                          size: 32,
                          color: AppColors.primary,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '上傳大頭貼',
                style: TextStyle(color: AppColors.businessCardContactText),
              ),
              const SizedBox(height: 24),

              _field(
                '姓名',
                nameCtrl,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '請填寫姓名' : null,
              ),
              _field('公司名稱', companyCtrl),
              _field('職稱', titleCtrl),
              _field('專長（以逗號分隔）', skillsCtrl),
              _field(
                '電子郵件',
                emailCtrl,
                keyboard: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return '請填寫 Email';
                  return v.contains('@') ? null : 'Email 格式不正確';
                },
              ),

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '社群連結',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final p in kPlatforms) _socialLinkCard(p),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('儲存'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _socialLinkCard(String platform) {
    final label = platform[0].toUpperCase() + platform.substring(1);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label[0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Text('啟用'),
                    Switch(
                      value: _active[platform] ?? false,
                      onChanged: (v) => setState(() => _active[platform] = v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            TextFormField(
              controller: _urlCtrls[platform],
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com/your-id',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if ((v ?? '').isEmpty) return null; // 可留空
                return v!.startsWith('http') ? null : '請輸入有效網址（以 http(s) 開頭）';
              },
            ),
            const SizedBox(height: 8),

            TextFormField(
              controller: _nameCtrls[platform],
              decoration: const InputDecoration(
                labelText: '顯示名稱（可選）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
