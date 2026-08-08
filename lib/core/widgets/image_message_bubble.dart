import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'media_upload_progress_ring.dart';

class ImageMessageBubble extends StatelessWidget {
  final String? imageUrl;
  final File? localFile;
  final double progress;
  final bool failed;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  const ImageMessageBubble({
    super.key,
    this.imageUrl,
    this.localFile,
    this.progress = 0,
    this.failed = false,
    this.onRetry,
    this.onCancel,
    this.onTap,
  });

  bool get _isPending => localFile != null;

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
              if (_isPending)
                Image.file(localFile!, fit: BoxFit.cover)
              else if (imageUrl != null && imageUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => Container(color: Colors.black26),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_rounded, color: Colors.white70),
                  ),
                )
              else
                Container(color: Colors.black26),
              if (_isPending)
                Container(
                  color: Colors.black26,
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
