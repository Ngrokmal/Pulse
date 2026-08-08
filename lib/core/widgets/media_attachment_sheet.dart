import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum AttachmentOption { galleryImage, cameraImage, video, file }

class MediaAttachmentSheet extends StatelessWidget {
  const MediaAttachmentSheet({super.key});

  static Future<AttachmentOption?> show(BuildContext context) {
    return showModalBottomSheet<AttachmentOption>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const MediaAttachmentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.medium),
        child: Wrap(
          runSpacing: AppSpacing.medium,
          alignment: WrapAlignment.spaceAround,
          children: [
            _AttachmentTile(
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              onTap: () => Navigator.pop(context, AttachmentOption.galleryImage),
            ),
            _AttachmentTile(
              icon: Icons.photo_camera_rounded,
              label: 'Camera',
              onTap: () => Navigator.pop(context, AttachmentOption.cameraImage),
            ),
            _AttachmentTile(
              icon: Icons.videocam_rounded,
              label: 'Video',
              onTap: () => Navigator.pop(context, AttachmentOption.video),
            ),
            _AttachmentTile(
              icon: Icons.insert_drive_file_rounded,
              label: 'File',
              onTap: () => Navigator.pop(context, AttachmentOption.file),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AttachmentTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: AppColors.inputBackground, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryAccent),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
