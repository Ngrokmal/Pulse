import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../profile/presentation/widgets/photo_placeholder.dart';

/// Large circular peer avatar shown on the Incoming/Outgoing/Active call
/// screens. Reuses [PhotoPlaceholder] (the same fallback-gradient +
/// cached-network-image widget already used across Profile/Chat) rather
/// than introducing a second avatar implementation.
class CallPeerAvatar extends StatelessWidget {
  final String? avatarUrl;
  final double size;

  const CallPeerAvatar({super.key, this.avatarUrl, this.size = 132});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 2),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 24, spreadRadius: 2)],
      ),
      clipBehavior: Clip.antiAlias,
      child: PhotoPlaceholder(imageUrl: avatarUrl, iconSize: size * 0.42),
    );
  }
}
