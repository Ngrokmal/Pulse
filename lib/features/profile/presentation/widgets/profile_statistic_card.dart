import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_duration.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Reusable statistic tile (e.g. "12 Mutual Friends"). Presentation-only —
/// takes a plain [value]/[label], never reads a bloc.
class ProfileStatisticCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const ProfileStatisticCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppDuration.bearCover,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.button,
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.medium, horizontal: AppSpacing.small),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.button,
              boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: AppColors.primaryAccent),
                const SizedBox(height: 6),
                Text(value, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
