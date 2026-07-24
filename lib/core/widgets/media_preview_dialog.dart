import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class MediaPreviewResult {
  final String caption;
  const MediaPreviewResult(this.caption);
}

class MediaPreviewDialog extends StatefulWidget {
  final File file;
  final bool isVideo;

  const MediaPreviewDialog({super.key, required this.file, this.isVideo = false});

  static Future<MediaPreviewResult?> show(
    BuildContext context, {
    required File file,
    bool isVideo = false,
  }) {
    return showDialog<MediaPreviewResult>(
      context: context,
      builder: (context) => MediaPreviewDialog(file: file, isVideo: isVideo),
    );
  }

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  final TextEditingController _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;
    // PHASE 2 FIX: cap the dialog's height against the *keyboard-adjusted*
    // available height, and let the preview image + caption scroll inside
    // that cap. The Cancel/Send row lives outside the scroll area so it is
    // always laid out last and is guaranteed to be on-screen and tappable,
    // no matter how much room the keyboard takes.
    final maxDialogHeight = screenHeight - viewInsets.bottom - 120;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight.clamp(200, double.infinity)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.medium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 260,
                          height: 220,
                          child: widget.isVideo
                              ? Container(
                                  color: Colors.black,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    color: Colors.white70,
                                    size: 56,
                                  ),
                                )
                              : Image.file(widget.file, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.small),
                      TextField(
                        controller: _captionController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption…',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.small),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(context, MediaPreviewResult(_captionController.text.trim())),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
