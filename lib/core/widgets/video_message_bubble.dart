import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'media_upload_progress_ring.dart';

class VideoMessageBubble extends StatelessWidget {
  final String? thumbnailUrl;
  final File? localFile;
  final int? durationMs;
  final double progress;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  const VideoMessageBubble({
    super.key,
    this.thumbnailUrl,
    this.localFile,
    this.durationMs,
    this.progress = 0,
    this.failed = false,
    this.onRetry,
    this.onCancel,
    this.onTap,
  });

  bool get _isPending => localFile != null;

  String get _durationLabel {
    final ms = durationMs ?? 0;
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isPending ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
                Image.network(
                  thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(color: AppColors.surface),
                )
              else
                Container(
                  color: AppColors.surface,
                  alignment: Alignment.center,
                  child: const Icon(Icons.videocam_rounded, size: 48, color: Colors.white38),
                ),
              if (!_isPending)
                Container(
                  alignment: Alignment.center,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                  ),
                ),
              if (!_isPending && durationMs != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_durationLabel, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              if (_isPending)
                Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: MediaUploadProgressRing(
                    progress: progress,
                    failed: failed,
                    onRetry: onRetry,
                    onCancel: onCancel,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
