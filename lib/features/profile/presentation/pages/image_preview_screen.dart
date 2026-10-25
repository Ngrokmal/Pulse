import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/photo_flow_result.dart';
import '../widgets/photo_placeholder.dart';

class ImagePreviewScreen extends StatelessWidget {
  final bool isCircle;
  final File imageFile;

  const ImagePreviewScreen({super.key, required this.isCircle, required this.imageFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
              child: Row(
                children: [
                  Text('Preview', style: AppTypography.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: isCircle
                    ? ClipOval(
                        child: SizedBox(width: 240, height: 240, child: PhotoPlaceholder(iconSize: 72, imageFile: imageFile)),
                      )
                    : AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
                          child: ClipRRect(
                            borderRadius: AppRadius.button,
                            child: PhotoPlaceholder(icon: Icons.photo_rounded, iconSize: 56, imageFile: imageFile),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.medium),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(PhotoFlowResult.confirmed(imageFile)),
                      child: const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Edit Again', style: AppTypography.body.copyWith(color: AppColors.primaryAccent)),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(const PhotoFlowResult.cancelled()),
                          child: Text('Cancel', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
