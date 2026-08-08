import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/services/friend_profile_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../call/domain/entities/call_type.dart';
import '../../../call/presentation/navigation/call_navigator.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/entities/verification_status.dart';
import '../../../profile/domain/usecases/stream_profile_usecase.dart';
import '../../../profile/presentation/pages/friend_profile_screen.dart';
import '../../../profile/presentation/widgets/verification_badge.dart';

class ChatAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String friendUid;
  final String currentUserId;

  const ChatAppBar({super.key, required this.friendUid, required this.currentUserId});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<ChatAppBar> createState() => _ChatAppBarState();
}

class _ChatAppBarState extends State<ChatAppBar> {
  late final Stream<ProfileEntity> _profileStream;
  ProfileEntity? _initialCached;

  @override
  void initState() {
    super.initState();
    _initialCached = FriendProfileCacheService.instance.getCachedSync(widget.friendUid);
    _profileStream = di.sl<StreamProfileUseCase>().call(widget.friendUid);
  }

  void _openProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(uid: widget.friendUid, viewerUid: widget.currentUserId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.call_rounded, color: AppColors.textPrimary),
          tooltip: 'Audio call',
          onPressed: () => CallNavigator.pushOutgoingCall(
            currentUserId: widget.currentUserId,
            calleeId: widget.friendUid,
            callType: CallType.audio,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.videocam_rounded, color: AppColors.textPrimary),
          tooltip: 'Video call',
          onPressed: () => CallNavigator.pushOutgoingCall(
            currentUserId: widget.currentUserId,
            calleeId: widget.friendUid,
            callType: CallType.video,
          ),
        ),
      ],
      title: StreamBuilder<ProfileEntity>(
        stream: _profileStream,
        builder: (context, snapshot) {
          final bool isLiveSnapshot = snapshot.hasData;
          final ProfileEntity? profile = snapshot.data ?? _initialCached;

          if (isLiveSnapshot && snapshot.data != null) {
            FriendProfileCacheService.instance.saveIfChanged(snapshot.data!);
          }

          final String name = (profile?.displayName.isNotEmpty ?? false) ? profile!.displayName : 'Chat';
          final bool hasPhoto = profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty;
          final VerificationStatus verificationStatus =
              profile?.verificationStatus ?? VerificationStatus.notVerified;

          final String statusLine = profile == null
              ? ''
              : (!isLiveSnapshot && profile.isOnline)
                  ? ''
                  : profile.isOnline
                      ? 'Online'
                      : (profile.lastSeen != null ? formatLastSeen(profile.lastSeen!) : '');

          return InkWell(
            onTap: () => _openProfile(context),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  backgroundImage: hasPhoto ? ProfileImageCache.instance.providerFor(profile!.avatarUrl!) : null,
                  onBackgroundImageError: hasPhoto ? (_, __) {} : null,
                  child: hasPhoto ? null : const Icon(Icons.person, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          VerificationBadge(status: verificationStatus, size: 15),
                        ],
                      ),
                      if (statusLine.isNotEmpty)
                        Text(
                          statusLine,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
