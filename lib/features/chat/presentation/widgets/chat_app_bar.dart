import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/services/friend_profile_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/usecases/stream_profile_usecase.dart';
import '../../../profile/presentation/pages/friend_profile_screen.dart';

/// WhatsApp-style chat header: avatar + name + online/last-seen, replacing
/// the previous plain `AppBar(title: Text('Chat Room'))`.
///
/// Task 2 (local cache): the very first frame is painted from
/// [FriendProfileCacheService] (disk) if a cached entry exists for this
/// friend, so there's no blank/loading header while the Firestore snapshot
/// is in flight. The live `StreamProfileUseCase` (same one already used by
/// ProfileBloc/home_screen.dart's chat-list tile — no new Firestore access
/// pattern introduced) then keeps it current; every snapshot is written
/// back to the cache, but only when it actually changed
/// (`saveIfChanged`), so an unchanged profile never triggers a disk write,
/// and the avatar URL never changes unless the photo itself changed —
/// `ProfileImageCache`/`cached_network_image` handle not re-downloading
/// the image bytes for an unchanged URL, unrelated to this text cache.
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
      title: StreamBuilder<ProfileEntity>(
        stream: _profileStream,
        initialData: _initialCached,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final bool isLiveSnapshot = snapshot.connectionState != ConnectionState.waiting;

          // FIX 1: only write to disk cache once we have a *real* Firestore
          // snapshot — never re-save the seed/initialData back onto itself.
          if (profile != null && isLiveSnapshot) {
            FriendProfileCacheService.instance.saveIfChanged(profile);
          }

          final String name = (profile?.displayName.isNotEmpty ?? false) ? profile!.displayName : 'Chat';
          final bool hasPhoto = profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty;

          // FIX 1 (stale cached online status), refined: an offline cached
          // value is safe to show immediately (a last-seen timestamp isn't
          // claiming "online right now", so a long-offline user still shows
          // their last-seen instead of a blank line). Only the *Online*
          // claim from the cached seed is untrustworthy — that specifically
          // is withheld until the live stream actually confirms it.
          final String statusLine = profile == null
              ? ''
              : (!isLiveSnapshot && profile.isOnline)
                  ? '' // cached "Online" seed — unconfirmed, don't show yet
                  : profile.isOnline
                      ? 'Online' // only reachable once isLiveSnapshot is true
                      : (profile.lastSeen != null ? formatLastSeen(profile.lastSeen!) : '');

          return InkWell(
            onTap: () => _openProfile(context),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  backgroundImage: hasPhoto ? ProfileImageCache.instance.providerFor(profile!.avatarUrl!) : null,
                  child: hasPhoto ? null : const Icon(Icons.person, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
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
