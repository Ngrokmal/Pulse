import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// UI-polish pass (presentation-layer only): replaces bare
/// `Center(child: Text(state.message))` error rendering with a consistent,
/// theme-aware visual. Purely presentational — the caller still owns
/// deciding *when* to show it (based on the existing `*ErrorState` from the
/// locked bloc layer); this widget never reads or retries bloc state itself.
class ErrorStateView extends StatelessWidget {
  final String message;

  const ErrorStateView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: AppDuration.medium,
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(opacity: value, child: child),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.error),
              const SizedBox(height: AppSpacing.small),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
