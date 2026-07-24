import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_duration.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Reusable action button used across Friend/Non-Friend/My profile
/// screens (Message, Audio Call, Video Call, Block, Report, Add Friend...).
/// UI only — callers pass [onTap]; no logic lives here.
class ProfileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// When true, renders as the prominent filled/primary action
  /// (typically the first button, e.g. "Message" / "Add Friend").
  final bool isPrimary;

  /// When true, tints the icon/label with the destructive error color
  /// (Block / Report).
  final bool isDestructive;

  const ProfileActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = isDestructive
        ? AppColors.error
        : isPrimary
            ? Colors.white
            : AppColors.textPrimary;

    final BoxDecoration decoration = isPrimary
        ? BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryAccent]),
            borderRadius: AppRadius.button,
            boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 6))],
          )
        : BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.button,
            border: isDestructive ? Border.all(color: AppColors.error.withOpacity(0.4)) : null,
          );

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.button,
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.small + 4),
            decoration: decoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
