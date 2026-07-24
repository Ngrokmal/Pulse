import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MediaUploadProgressRing extends StatelessWidget {
  final double progress;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final double size;

  const MediaUploadProgressRing({
    super.key,
    required this.progress,
    this.failed = false,
    this.onRetry,
    this.onCancel,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!failed)
            SizedBox(
              width: size - 8,
              height: size - 8,
              child: CircularProgressIndicator(
                value: progress <= 0 ? null : progress.clamp(0, 1),
                strokeWidth: 2.5,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          GestureDetector(
            onTap: failed ? onRetry : onCancel,
            child: Icon(
              failed ? Icons.refresh_rounded : Icons.close_rounded,
              color: failed ? AppColors.error : Colors.white,
              size: size * 0.45,
            ),
          ),
        ],
      ),
    );
  }
}
