import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  const ScrollToBottomButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
