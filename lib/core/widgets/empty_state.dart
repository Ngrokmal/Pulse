import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// UI-polish pass (presentation-layer only, Day 6 M3 follow-up):
/// shared empty-state visual for chat list / message list / member list
/// screens. Pure UI — takes no bloc/repository dependency, just text + icon.
/// Fades and gently slides up on first build (TweenAnimationBuilder, no
/// external animation controller to manage/dispose).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: AppDuration.bearCover,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 12),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.medium),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 36, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.medium),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.small),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
