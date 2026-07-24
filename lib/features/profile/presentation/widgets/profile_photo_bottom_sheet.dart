import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// What the user picked in [ProfilePhotoBottomSheet]. UI-only signal —
/// the caller decides what (if anything) to do with it.
enum ProfilePhotoAction { viewPhoto, gallery, camera, remove }

/// Reusable bottom sheet shared by both the Profile Photo and Cover
/// Photo tap targets. UI only: it never touches storage/upload, it just
/// resolves to a [ProfilePhotoAction] for the caller to act on.
class ProfilePhotoBottomSheet extends StatelessWidget {
  final String title;
  final bool hasExistingPhoto;

  const ProfilePhotoBottomSheet({
    super.key,
    required this.title,
    this.hasExistingPhoto = true,
  });

  static Future<ProfilePhotoAction?> show(
    BuildContext context, {
    required String title,
    bool hasExistingPhoto = true,
  }) {
    return showModalBottomSheet<ProfilePhotoAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ProfilePhotoBottomSheet(title: title, hasExistingPhoto: hasExistingPhoto),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.small),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.small),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(4)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: AppSpacing.small),
            if (hasExistingPhoto)
              _Option(
                icon: Icons.visibility_outlined,
                label: 'View Photo',
                onTap: () => Navigator.of(context).pop(ProfilePhotoAction.viewPhoto),
              ),
            _Option(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Gallery',
              onTap: () => Navigator.of(context).pop(ProfilePhotoAction.gallery),
            ),
            _Option(
              icon: Icons.camera_alt_outlined,
              label: 'Take Photo',
              onTap: () => Navigator.of(context).pop(ProfilePhotoAction.camera),
            ),
            if (hasExistingPhoto)
              _Option(
                icon: Icons.delete_outline_rounded,
                label: 'Remove Photo',
                destructive: true,
                onTap: () => Navigator.of(context).pop(ProfilePhotoAction.remove),
              ),
            const SizedBox(height: AppSpacing.small),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _Option({required this.icon, required this.label, required this.onTap, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final Color color = destructive ? AppColors.error : AppColors.textPrimary;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: destructive ? AppColors.error : AppColors.primaryAccent),
      title: Text(label, style: AppTypography.body.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
