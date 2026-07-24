import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../pages/image_crop_screen.dart';
import 'photo_flow_result.dart';
import 'photo_placeholder.dart';
import 'profile_photo_bottom_sheet.dart';

class ProfilePhotoFlow {
  ProfilePhotoFlow._();

  static final ImagePicker _picker = ImagePicker();

  static Future<void> start(
    BuildContext context, {
    required String title,
    required bool isCircle,
    bool hasExistingPhoto = true,
    String? currentImageUrl,
    required ValueChanged<File> onPhotoSelected,
    VoidCallback? onRemove,
  }) async {
    final action = await ProfilePhotoBottomSheet.show(context, title: title, hasExistingPhoto: hasExistingPhoto);
    if (action == null || !context.mounted) return;

    switch (action) {
      case ProfilePhotoAction.viewPhoto:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _PhotoViewScreen(isCircle: isCircle, title: title, imageUrl: currentImageUrl)),
        );
        break;
      case ProfilePhotoAction.gallery:
      case ProfilePhotoAction.camera:
        XFile? picked;
        try {
          picked = await _picker.pickImage(
            source: action == ProfilePhotoAction.camera ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 90,
          );
        } catch (_) {
          if (context.mounted) _showSnack(context, 'Could not open the picker. Please try again.');
          return;
        }
        if (picked == null || !context.mounted) return;

        final result = await Navigator.of(context).push<PhotoFlowResult>(
          MaterialPageRoute(builder: (_) => ImageCropScreen(isCircle: isCircle, sourceFile: File(picked!.path))),
        );
        if (result != null && !result.cancelled && result.file != null) {
          onPhotoSelected(result.file!);
        }
        break;
      case ProfilePhotoAction.remove:
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Remove Photo?'),
            content: Text('This will remove your $title.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Remove', style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          onRemove?.call();
        }
        break;
    }
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PhotoViewScreen extends StatelessWidget {
  final bool isCircle;
  final String title;
  final String? imageUrl;
  const _PhotoViewScreen({required this.isCircle, required this.title, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(title), foregroundColor: Colors.white),
      body: Center(
        child: isCircle
            ? ClipOval(child: SizedBox(width: 260, height: 260, child: PhotoPlaceholder(iconSize: 80, imageUrl: imageUrl)))
            : Padding(
                padding: const EdgeInsets.all(24),
                child: AspectRatio(aspectRatio: 16 / 9, child: PhotoPlaceholder(icon: Icons.photo_rounded, iconSize: 60, imageUrl: imageUrl)),
              ),
      ),
    );
  }
}
