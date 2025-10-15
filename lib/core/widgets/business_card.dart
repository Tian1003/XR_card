import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:auto_size_text/auto_size_text.dart';

import 'package:my_app/core/theme/app_colors.dart'; // 依你的實際路徑
import 'package:my_app/core/widgets/social_links_list.dart'; // 前面我們做的 SocialLinksList
import 'package:my_app/data/models/user_complete_profile.dart';

/// 上方名片區塊（可重用）
class BusinessCard extends StatelessWidget {
  final UserCompleteProfile profile;

  const BusinessCard({super.key, required this.profile});

  /// 處理點擊 Email 的函式
  Future<void> _launchEmail(BuildContext context, String? email) async {
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email 地址無效')));
      return;
    }

    final Uri emailLaunchUri = Uri(scheme: 'mailto', path: email);

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      // 若無法開啟 mailto，則複製到剪貼簿
      Clipboard.setData(ClipboardData(text: email));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟郵件應用，已將 Email 複製到剪貼簿')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8), // 外層邊框間距
      decoration: BoxDecoration(
        color: AppColors.primary, // 深綠色外框
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 50), // 左、上、右、下
        decoration: BoxDecoration(
          color: AppColors.background, // 更亮的淺灰色背景
          borderRadius: BorderRadius.circular(70),
        ),
        child: Column(
          children: [
            // 頭像
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.avatarBorder, width: 4),
              ),
              child: CircleAvatar(
                radius: 74.5,
                backgroundImage: (profile.avatarUrl ?? '').isNotEmpty
                    ? NetworkImage(profile.avatarUrl!)
                    : null,
                backgroundColor: Colors.grey.shade200,
                child: (profile.avatarUrl ?? '').isEmpty
                    ? Icon(
                        Icons.person,
                        size: 90, // 明確指定圖示大小
                        color: Colors.grey.shade400, // 設定一個柔和的顏色
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 4),

            // 姓名
            AutoSizeText(
              profile.username.isNotEmpty ? profile.username : '未知用戶',
              maxLines: 1, // 強制一行
              minFontSize: 20, // 最小字體（避免縮太小看不清）
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
                letterSpacing:
                    RegExp(r'[\u4e00-\u9fff]').hasMatch(profile.username)
                    ? 7
                    : 1, // 中文字符增加間距
              ),
            ),
            const SizedBox(height: 4),

            // 公司
            AutoSizeText(
              profile.company?.isNotEmpty == true ? profile.company! : '未知公司',
              maxLines: 1, // 強制一行
              minFontSize: 20, // 最小字體（避免縮太小看不清）
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryLight,
                letterSpacing: 1,
              ),
            ),

            // 分隔線
            Container(
              height: 2.5,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 20),

            // 職稱
            labeledWrap(label: '職稱：', value: profile.jobTitle ?? '未知職稱'),
            const SizedBox(height: 6),
            // 專長
            labeledWrap(label: '專長：', value: profile.skill ?? '未知專長'),
            const SizedBox(height: 24),

            // 聯絡資訊標題
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '聯絡資訊',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.businessCardContactText,
                  fontSize: 26,
                ),
              ),
            ),

            // 分隔線
            Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 18),

            // Email
            InkWell(
              onTap: () => _launchEmail(context, profile.email),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F4F4F),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.email_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AutoSizeText(
                      ': ${(profile.email?.isNotEmpty == true) ? profile.email! : '未提供 Email'}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: AppColors.businessCardText,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      minFontSize: 12,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 加入和社群連結一樣的圖示
                  const SizedBox(width: 8),
                  const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
                ],
              ),
            ),

            // 社群連結
            SocialLinksList(socialLinks: profile.socialLinks),
          ],
        ),
      ),
    );
  }
}

/// 職稱、專長：帶有標籤的文字包裝
Widget labeledWrap({required String label, required String value}) {
  return Align(
    alignment: Alignment.centerLeft,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 20,
            color: AppColors.businessCardText,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: const TextStyle(
              fontSize: 20,
              color: AppColors.businessCardText,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class BuildButton extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback? onPressed;

  const BuildButton({
    super.key,
    required this.text,
    required this.isSelected,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 167,
        height: 65,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : const Color.fromRGBO(219, 218, 217, 1.0),
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    offset: const Offset(0, 3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.2),
                    offset: Offset(-1.8, -1.8),
                    blurRadius: 2,
                  ),
                  const BoxShadow(
                    color: Color.fromRGBO(255, 255, 255, 1),
                    offset: Offset(1, 1),
                    blurRadius: 4,
                  ),
                ],
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.primary,
              fontWeight: FontWeight.w900,
              fontSize: 26,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
