import 'package:flutter/material.dart';
import 'package:my_app/data/models/user_complete_profile.dart';

class XrBusinessCard extends StatelessWidget {
  final UserCompleteProfile? profile;
  final VoidCallback? onAnalyzePressed; // 企業分析
  final VoidCallback? onRecordPressed; // 對話回顧
  final VoidCallback? onChatPressed; // 話題建議

  const XrBusinessCard({
    super.key,
    this.profile,
    this.onAnalyzePressed,
    this.onRecordPressed,
    this.onChatPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const SizedBox.shrink();
    }

    return Card(
      color: Colors.black.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      (profile!.avatarUrl != null &&
                          profile!.avatarUrl!.isNotEmpty)
                      ? NetworkImage(profile!.avatarUrl!)
                      : null,
                  backgroundColor: Colors.grey.shade700,
                  child:
                      (profile!.avatarUrl == null ||
                          profile!.avatarUrl!.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile!.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${profile!.company ?? '未提供公司'} ${profile!.jobTitle ?? ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8.0,
              runSpacing: 6.0,
              alignment: WrapAlignment.center,
              children: [
                _buildActionButton('企業分析', onPressed: onAnalyzePressed),
                _buildActionButton('對話回顧', onPressed: onRecordPressed),
                _buildActionButton('話題建議', onPressed: onChatPressed),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, {required VoidCallback? onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.2),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(text),
    );
  }
}
