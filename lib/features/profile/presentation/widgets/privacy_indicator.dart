import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Small pill communicating that a section of a non-friend's profile is
/// hidden until they connect (e.g. "Add friends to see more").
class PrivacyIndicator extends StatelessWidget {
  final String message;
  final IconData icon;

  const PrivacyIndicator({
    super.key,
    this.message = 'Some info is only visible to friends',
    this.icon = Icons.lock_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.small),
          Expanded(child: Text(message, style: AppTypography.caption)),
        ],
      ),
    );
  }
}
