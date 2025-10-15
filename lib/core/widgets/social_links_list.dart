import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:auto_size_text/auto_size_text.dart';

import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/core/theme/social_platform_config.dart';
import 'package:my_app/data/models/user_complete_profile.dart';

class SocialLinksList extends StatelessWidget {
  final List<SocialLink> socialLinks;
  final TextStyle textStyle;
  final double itemSpacing;
  final double badgeSize;

  const SocialLinksList({
    super.key,
    required this.socialLinks,
    this.textStyle = const TextStyle(
      fontSize: 20,
      color: AppColors.businessCardText,
      fontWeight: FontWeight.w700,
    ),
    this.itemSpacing = 14,
    this.badgeSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final items = _buildSocialLinks(context, socialLinks);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(children: items);
  }

  List<Widget> _buildSocialLinks(
    BuildContext context,
    List<SocialLink> socialLinks,
  ) {
    final List<Widget> widgets = [];

    try {
      // 只顯示 isActive 且有 URL 的，並依 display_order 排序
      final filtered =
          socialLinks
              .where((l) => l.isActive && l.url.trim().isNotEmpty)
              .toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

      for (final link in filtered) {
        final style = SocialPlatformConfig.get(link.platform);
        if (style == null) continue;

        final String title =
            (link.displayName != null && link.displayName!.trim().isNotEmpty)
            ? link.displayName!.trim()
            : link.platform;

        widgets.add(SizedBox(height: itemSpacing));

        widgets.add(
          InkWell(
            onTap: () => _openUrl(context, link.url), // 點擊開啟
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: link.url));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已複製連結')));
            },
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center, // 改回垂直置中
              children: [
                // 平台徽章
                Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: style.color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: style.isText
                      ? Center(
                          child: Text(
                            style.icon as String, // 例如 "in"
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : Icon(
                          style.icon as IconData,
                          color: Colors.white,
                          size: 18,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // 自動調整文字大小
                  child: AutoSizeText(
                    ': ${title.isNotEmpty ? title : link.url}',
                    style: textStyle,
                    maxLines: 1,
                    minFontSize: 12,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
              ],
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Error building social links: $e\n$st');
    }

    return widgets;
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('網址格式不正確')));
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('無法開啟：$url')));
    }
  }
}
