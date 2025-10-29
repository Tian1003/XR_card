import 'package:flutter/material.dart';
import 'package:my_app/core/theme/app_colors.dart';
import 'package:my_app/features/xr_simulator/xr_simulator_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // <--- [新增] 引入 Supabase

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  bool _isResetting = false; // 用於管理重置功能的讀取狀態

  // 導航到 XR 模擬器頁面的方法
  void _navigateToXrSimulator(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const XrSimulatorPage()),
    );
  }

  // 重置 Demo 的處理函數
  Future<void> _resetDemo() async {
    if (_isResetting) return; // 防止重複點擊

    setState(() => _isResetting = true); // 開始重置，顯示讀取狀態

    try {
      // 直接在這裡執行 Supabase 刪除操作
      await Supabase.instance.client
          .from('contacts') // 根據您的 SQL 檔，表名是 'contacts'
          .delete()
          .or(
            'and(requester_id.eq.1,friend_id.eq.2),and(requester_id.eq.2,friend_id.eq.1)',
          );

      if (!mounted) return; // 檢查 Widget 是否還存在
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('Reset Demo 成功'),
      //     backgroundColor: Colors.green,
      //   ),
      // );
    } catch (e) {
      if (!mounted) return; // 檢查 Widget 是否還存在
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset Demo 失敗: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isResetting = false); // 結束重置
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Setting',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(
            color: AppColors.primary,
            child: SizedBox(height: 3),
          ),
        ),
      ),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionTitle(context, '實驗性功能'),

          // 開啟模擬功能的選項
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '開啟模擬功能',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _navigateToXrSimulator(context),
                    child: const Text('啟動'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionTitle(context, '帳號設定'),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              title: const Text('帳號設定'), // <--- [修改] 文字保持原樣
              trailing: _isResetting
                  ? const SizedBox(
                      // [修改] 讀取時顯示轉圈
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                    ), // [修改] 預設顯示箭頭
              onTap: _isResetting
                  ? null
                  : _resetDemo, // <--- [修改] 點擊時觸發 _resetDemo
            ),
          ),

          const SizedBox(height: 24), // 與下一區塊間隔

          _buildSectionTitle(context, '其他設定'),
          // ... (其他設定 Card 保持不變)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: const ListTile(
              title: Text('通知設定'),
              trailing: Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // 抽出一個建立區塊標題的 widget
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 8.0, left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
