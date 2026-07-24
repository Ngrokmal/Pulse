import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';

/// Single square media tile for a profile's shared-media grid.
/// UI only — no actual media is loaded, a placeholder icon stands in.
class MediaPreviewCard extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const MediaPreviewCard({super.key, this.icon = Icons.image_rounded, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.input,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.input,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.textSecondary, size: 26),
        ),
      ),
    );
  }
}
