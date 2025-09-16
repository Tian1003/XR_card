import 'package:flutter/material.dart';

import 'package:my_app/core/theme/app_colors.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int>? onTap; // 允許 null

  const BottomNavBar({Key? key, required this.currentIndex, this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.primary, width: 3), // 上方加線
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary, // 自訂顏色
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.contact_page, size: 38),
            label: 'Contact',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person, size: 38),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth, size: 38),
            label: 'Connect',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings, size: 38),
            label: 'Setting',
          ),
        ],
      ),
    );
  }
}
