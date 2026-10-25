import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'media_upload_progress_ring.dart';

class FileMessageBubble extends StatelessWidget {
  final String fileName;
  final int? fileSizeBytes;
  final String? mediaUrl;
  final double progress;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onDownload;

  const FileMessageBubble({
    super.key,
    required this.fileName,
    this.fileSizeBytes,
    this.mediaUrl,
    this.progress = 0,
    this.failed = false,
    this.onRetry,
    this.onCancel,
    this.onDownload,
  });

  bool get _isPending => mediaUrl == null || mediaUrl!.isEmpty;

  String get _sizeLabel {
    final bytes = fileSizeBytes ?? 0;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData get _icon {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.grid_on_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: _isPending
                ? MediaUploadProgressRing(
                    progress: progress,
                    failed: failed,
                    onRetry: onRetry,
                    onCancel: onCancel,
                    size: 44,
                  )
                : GestureDetector(
                    onTap: onDownload,
                    child: Container(
                      decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(_icon, color: AppColors.primaryAccent),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.small),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(color: AppColors.textPrimary),
                ),
                if (_sizeLabel.isNotEmpty)
                  Text(_sizeLabel, style: AppTypography.caption),
              ],
            ),
          ),
          if (!_isPending)
            IconButton(
              icon: const Icon(Icons.download_rounded, color: AppColors.primaryAccent),
              onPressed: onDownload,
            ),
        ],
      ),
    );
  }
}
