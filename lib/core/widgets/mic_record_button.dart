import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MicRecordButton extends StatelessWidget {
  final VoidCallback onTap;

  const MicRecordButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_none_rounded, color: Colors.white),
      ),
    );
  }
}
