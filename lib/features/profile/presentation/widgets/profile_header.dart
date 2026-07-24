import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_duration.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'photo_placeholder.dart';

/// Reusable, premium profile header shared by My/Friend/Non-Friend
/// profile screens: cover image + large animated avatar (Hero) + name/
/// username/bio. Every visual affordance (edit badges, camera taps) is
/// opt-in via callbacks so the same widget serves all three screens.
class ProfileHeader extends StatelessWidget {
  final String heroTag;
  final String name;
  final String username;
  final String? bio;
  final bool isOnline;
  final bool showOnlineStatus;
  final DateTime? lastSeen;
  final String? avatarUrl;
  final String? coverUrl;
  final Widget? verificationBadge;

  /// Shows a camera badge over the avatar/cover and calls back on tap.
  /// Used only on "My Profile".
  final bool editable;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onCoverTap;

  const ProfileHeader({
    super.key,
    required this.heroTag,
    required this.name,
    required this.username,
    this.bio,
    this.isOnline = false,
    this.showOnlineStatus = true,
    this.lastSeen,
    this.avatarUrl,
    this.coverUrl,
    this.verificationBadge,
    this.editable = false,
    this.onAvatarTap,
    this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Cover image placeholder
            GestureDetector(
              onTap: onCoverTap,
              child: Hero(
                tag: '$heroTag-cover',
                child: SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PhotoPlaceholder(
                        icon: Icons.image_rounded,
                        colors: const [AppColors.backgroundTop, AppColors.surface],
                        imageUrl: coverUrl,
                      ),
                      // subtle bottom fade so the avatar overlaps cleanly
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppColors.backgroundBottom.withOpacity(0.55)],
                          ),
                        ),
                      ),
                      if (editable)
                        Positioned(
                          right: AppSpacing.medium,
                          bottom: AppSpacing.small,
                          child: _EditBadge(onTap: onCoverTap, icon: Icons.camera_alt_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // Avatar, overlapping the cover
            Positioned(
              bottom: -46,
              child: GestureDetector(
                onTap: onAvatarTap,
                child: Hero(
                  tag: '$heroTag-avatar',
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.backgroundBottom,
                      shape: BoxShape.circle,
                    ),
                    child: Stack(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: PhotoPlaceholder(iconSize: 44, imageUrl: avatarUrl),
                          ),
                        ),
                        if (showOnlineStatus && isOnline)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: const Color(0xff2ecc71),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.backgroundBottom, width: 3),
                              ),
                            ),
                          ),
                        if (editable)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: _EditBadge(onTap: onAvatarTap, icon: Icons.camera_alt_rounded, small: true),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 54),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: AppDuration.bearCover,
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: AppTypography.title.copyWith(fontSize: 22)),
                  if (verificationBadge != null) ...[
                    const SizedBox(width: 6),
                    verificationBadge!,
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(username, style: AppTypography.body.copyWith(color: AppColors.primaryAccent)),
              if (bio != null && bio!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.small),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
                  child: Text(
                    bio!,
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(color: AppColors.textPrimary, height: 1.4),
                  ),
                ),
              ],
              if (showOnlineStatus) ...[
                const SizedBox(height: AppSpacing.small),
                _OnlineStatusChip(isOnline: isOnline, lastSeen: lastSeen),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OnlineStatusChip extends StatelessWidget {
  final bool isOnline;
  final DateTime? lastSeen;
  const _OnlineStatusChip({required this.isOnline, this.lastSeen});

  String _label() {
    if (isOnline) return 'Online';
    if (lastSeen == null) return 'Offline';
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    if (diff.inDays < 7) return 'Last seen ${diff.inDays}d ago';
    return 'Last seen ${lastSeen!.day}/${lastSeen!.month}/${lastSeen!.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? const Color(0xff2ecc71) : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: AppDuration.medium,
            child: Text(
              _label(),
              key: ValueKey<String>('$isOnline-${lastSeen?.millisecondsSinceEpoch}'),
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditBadge extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final bool small;
  const _EditBadge({required this.onTap, required this.icon, this.small = false});

  @override
  Widget build(BuildContext context) {
    final double size = small ? 28 : 32;
    return Material(
      color: AppColors.primary,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: small ? 14 : 16, color: Colors.white),
        ),
      ),
    );
  }
}
