import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../blocs/profile_bloc.dart';

class UploadStatusBanner extends StatelessWidget {
  final String label;
  final PhotoUploadStatus status;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const UploadStatusBanner({
    super.key,
    required this.label,
    required this.status,
    required this.onRetry,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (status.stage == PhotoUploadStage.idle || status.stage == PhotoUploadStage.cancelled) {
      return const SizedBox.shrink();
    }

    final bool failed = status.stage == PhotoUploadStage.failed;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (!failed)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, value: status.progress > 0 ? status.progress : null),
              )
            else
              Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
            const SizedBox(width: AppSpacing.small),
            Expanded(
              child: Text(
                failed ? '$label upload failed' : 'Uploading $label…',
                style: AppTypography.caption,
              ),
            ),
            if (failed)
              TextButton(onPressed: onRetry, child: const Text('Retry'))
            else
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
