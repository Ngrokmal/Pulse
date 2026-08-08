import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';

class PhotoPlaceholder extends StatelessWidget {
  final IconData icon;
  final double? iconSize;
  final List<Color>? colors;
  final String? imageUrl;
  final File? imageFile;

  const PhotoPlaceholder({
    super.key,
    this.icon = Icons.person_rounded,
    this.iconSize,
    this.colors,
    this.imageUrl,
    this.imageFile,
  });

  @override
  Widget build(BuildContext context) {
    if (imageFile != null) {
      return Image.file(
        imageFile!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        key: ValueKey('avatar-$imageUrl'),
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (context, url) => _fallback(),
        errorWidget: (context, url, error) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? const [AppColors.primary, AppColors.primaryAccent],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize ?? 40, color: Colors.white.withOpacity(0.9)),
    );
  }
}
