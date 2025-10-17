import 'package:flutter/material.dart';
import 'dart:math' as math;

// 按鈕項目模型
class FabAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  FabAction({required this.label, required this.icon, required this.onPressed});
}

// 可展開的 FAB Widget
class ExpandingFab extends StatefulWidget {
  final List<FabAction> actions;

  const ExpandingFab({super.key, required this.actions});

  @override
  State<ExpandingFab> createState() => _ExpandingFabState();
}

class _ExpandingFabState extends State<ExpandingFab>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late final AnimationController _animationController;
  late final Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // 將旋轉動畫從 90 度改為 45 度，讓 "+" 變成 "x"
    _rotateAnimation = Tween<double>(begin: 0.0, end: 0.125).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 整個元件用 Row 來實現水平直線佈局
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 展開後的按鈕列表
        if (_isOpen)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var action in widget.actions.reversed)
                Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: _ActionChip(
                    label: action.label,
                    icon: action.icon,
                    onPressed: () {
                      _toggle();
                      action.onPressed();
                    },
                  ),
                ),
            ],
          ),

        // 主要的控制按鈕
        _MainActionButton(
          onPressed: _toggle,
          rotateAnimation: _rotateAnimation,
        ),
      ],
    );
  }
}

// 抽出的主按鈕
class _MainActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Animation<double> rotateAnimation;

  const _MainActionButton({
    required this.onPressed,
    required this.rotateAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: RotationTransition(
          turns: rotateAnimation,
          child: const Icon(Icons.add, color: Color(0xFF154549), size: 20),
        ),
      ),
    );
  }
}

// 展開後的單一功能按鈕樣式
class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
