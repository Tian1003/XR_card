import 'package:flutter/material.dart';
import 'package:my_app/features/contact/contact_page.dart';
import 'package:my_app/features/profile/profile_page.dart';
import 'package:my_app/features/connect/connect_page.dart';
import 'package:my_app/features/setting/setting_page.dart';
import 'package:my_app/core/widgets/bottom_nav_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 底部四頁
  static const int kIndexContact = 0;
  // static const int kIndexProfile = 1;
  // static const int kIndexConnect = 2;
  static const int kIndexSetting = 3;

  late final List<Widget> _pages;
  int _currentIndex = kIndexContact;

  @override
  void initState() {
    super.initState();
    _pages = [
      ContactPage(), // 0
      ProfilePage(), // 1
      ConnectPage(), // 2
      SettingPage(), // 3
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            // 點 bottom bar 只切 0~3
            _currentIndex = index.clamp(kIndexContact, kIndexSetting);
          });
        },
      ),
    );
  }
}
