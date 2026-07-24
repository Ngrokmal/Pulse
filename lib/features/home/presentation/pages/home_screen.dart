import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/services/friend_profile_cache_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/admin_access.dart';
import '../../../../core/utils/pending_chat_navigation.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../../admin/presentation/pages/admin_dashboard_screen.dart';
import '../blocs/chat_list_bloc.dart';
import '../../../auth/domain/usecases/logout_usecase.dart';
import '../../../auth/presentation/pages/auth_screen.dart';
import '../../../chat/presentation/pages/chat_screen.dart';
import '../../../chat/presentation/pages/create_group_screen.dart';
import '../../../chat/presentation/pages/group_chat_screen.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/usecases/stream_profile_usecase.dart';
import '../../../profile/presentation/blocs/profile_bloc.dart';
import '../../../profile/presentation/pages/my_profile_screen.dart';
import '../../../profile/presentation/widgets/photo_placeholder.dart';
import '../../../search/presentation/pages/search_screen.dart';

class HomeScreen extends StatefulWidget {
  final String currentUserId;
  const HomeScreen({super.key, required this.currentUserId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ChatListBloc _chatListBloc;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _chatListBloc = di.sl<ChatListBloc>()..add(LoadChatListEvent(widget.currentUserId));

    // Milestone 7.2 (Notification Handling): terminated-launch বা pre-login
    // অবস্থায় নোটিফিকেশন ট্যাপ হলে chatId এখানে pending থাকে (দেখুন
    // core/utils/pending_chat_navigation.dart) — লগইনের পর HomeScreen
    // বিল্ড হওয়ার প্রথম ফ্রেমের পরে সেটি consume করে সরাসরি ChatScreen-এ
    // নেভিগেট করা হয়।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingChatId = PendingChatNavigation.instance.consumePendingChatId();
      if (pendingChatId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(chatId: pendingChatId, currentUserId: widget.currentUserId),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatListBloc.close(); // ব্লক ও এর রিপোজিটরি স্ট্রিম সাবস্ক্রিপশন ক্লিনআপ
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatListBloc>.value(
      value: _chatListBloc,
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            // Phase 8.6A (Admin Foundation): hidden admin entry point. No
            // visible button for regular users — long-pressing the title
            // silently does nothing unless AdminAccess.isAdmin is true.
            onLongPress: () {
              if (!AdminAccess.isAdmin(widget.currentUserId)) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminDashboardScreen(uid: widget.currentUserId),
                ),
              );
            },
            child: const Text('Chats'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_search_rounded),
              tooltip: 'Find people',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SearchScreen(currentUserId: widget.currentUserId),
                  ),
                );
              },
            ),
            _ProfileMenuButton(currentUserId: widget.currentUserId),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final groupId = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => CreateGroupScreen(currentUserId: widget.currentUserId),
              ),
            );
            // CreateGroupScreen সফল হলে নতুন groupId নিয়ে pop করে (Milestone 1,
            // অপরিবর্তিত) — Milestone 2-এ শুধু এই ফলাফল ব্যবহার করে সরাসরি
            // GroupChatScreen-এ নেভিগেট করা যুক্ত হয়েছে, যাতে নতুন তৈরি হওয়া গ্রুপ
            // ব্যবহারযোগ্য হয় (Home list sync gap থাকলেও)।
            if (groupId != null && mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GroupChatScreen(
                    groupId: groupId,
                    currentUserId: widget.currentUserId,
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.group_add),
          label: const Text('New Group'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _chatListBloc.add(SearchChatListEvent(''));
                        },
                      );
                    },
                  ),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onChanged: (query) => _chatListBloc.add(SearchChatListEvent(query)),
              ),
            ),
            Expanded(
              child: BlocBuilder<ChatListBloc, ChatListState>(
                builder: (context, state) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildBody(context, state),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // UI-polish pass (presentation-layer only): state → widget mapping so
  // AnimatedSwitcher can cross-fade cleanly between loading/empty/error/
  // loaded — same ChatListState branches as before, no bloc field/logic
  // changed.
  Widget _buildBody(BuildContext context, ChatListState state) {
    if (state is ChatListLoading) {
      return const Center(
        key: ValueKey('home-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (state is ChatListLoadedState) {
      if (state.chats.isEmpty) {
        return EmptyState(
          key: const ValueKey('home-empty'),
          icon: state.searchQuery.isEmpty ? Icons.chat_bubble_outline : Icons.search_off,
          title: state.searchQuery.isEmpty
              ? 'No conversations yet'
              : 'No conversations match "${state.searchQuery}"',
          subtitle: state.searchQuery.isEmpty
              ? 'Start a new group or message someone to get going'
              : null,
        );
      }
      return ListView.separated(
        key: const ValueKey('home-loaded'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
        itemCount: state.chats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) => _ChatListTile(
          key: ValueKey(state.chats[index].chatId),
          chat: state.chats[index],
          currentUserId: widget.currentUserId,
        ),
      );
    }
    if (state is ChatListErrorState) {
      return ErrorStateView(key: const ValueKey('home-error'), message: state.message);
    }
    return const SizedBox.shrink(key: ValueKey('home-blank'));
  }
}

// UI-polish pass: extracted from the inline ListView.builder itemBuilder so
// the tile can carry its own Hero avatar + card styling. Reads only the
// existing `ChatListItemEntity` fields the original itemBuilder already
// used (chatId/isGroup/name/lastMessage/lastMessageAt/unreadCount/
// groupPhotoUrl) — no new field, no new navigation target.
class _ChatListTile extends StatefulWidget {
  final dynamic chat;
  final String currentUserId;

  const _ChatListTile({super.key, required this.chat, required this.currentUserId});

  @override
  State<_ChatListTile> createState() => _ChatListTileState();
}

class _ChatListTileState extends State<_ChatListTile> {
  // PHASE 1 FIX: 1:1 chat documents never store the friend's name/avatar
  // (only participantIds), so the tile previously had nothing to show and
  // fell back to the message text / raw timestamp instead. We resolve the
  // "other" participant's uid once and subscribe to their profile stream
  // (same StreamProfileUseCase already used by ProfileBloc) to get a live
  // name + avatarUrl. Stream is created once in initState (not inline in
  // build) so it isn't re-subscribed on every ChatListBloc rebuild.
  Stream<ProfileEntity>? _friendProfileStream;
  // Cache-first paint (same fix already applied in chat_app_bar.dart /
  // profile_bloc.dart): read the on-disk FriendProfileCacheService entry
  // synchronously so the tile shows the friend's real name/avatar on the
  // very first frame after reopening the app, instead of falling into the
  // ConnectionState.waiting -> "Loading..." branch below while the
  // Firestore snapshot is in flight. No new Firestore read is introduced —
  // this only seeds the StreamBuilder's initialData; the live
  // StreamProfileUseCase subscription below is unchanged.
  ProfileEntity? _initialCached;

  @override
  void initState() {
    super.initState();
    if (!widget.chat.isGroup) {
      final friendUid = widget.chat.participantIds.firstWhere(
        (id) => id != widget.currentUserId,
        orElse: () => '',
      );
      if (friendUid.isNotEmpty) {
        _initialCached = FriendProfileCacheService.instance.getCachedSync(friendUid);
        _friendProfileStream = di.sl<StreamProfileUseCase>().call(friendUid);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final currentUserId = widget.currentUserId;
    final unread = chat.unreadCount[currentUserId] ?? 0;

    // PHASE 1 FIX: last-message preview, computed the same way for both
    // groups and 1:1 chats (subtitle used to render the raw ISO timestamp
    // here — the friend's name/avatar could not be shown at all, and the
    // preview slot was fully unused).
    final String previewText = chat.lastMessage.isEmpty ? 'No messages yet' : chat.lastMessage;

    if (chat.isGroup) {
      // Day 5 Milestone 1: groupPhotoUrl থাকলে দেখানো হয়, না থাকলে/খালি
      // হলে ডিফল্ট group icon (GroupInfoScreen-এর fallback-এর সাথে সামঞ্জস্যপূর্ণ)।
      final hasPhoto = chat.groupPhotoUrl != null && chat.groupPhotoUrl!.isNotEmpty;
      return _buildTile(
        context: context,
        unread: unread,
        lastMessageAt: chat.lastMessageAt,
        avatar: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.2),
          backgroundImage: hasPhoto ? ProfileImageCache.instance.providerFor(chat.groupPhotoUrl!) : null,
          child: hasPhoto ? null : const Icon(Icons.group, color: AppColors.textPrimary),
        ),
        title: (chat.name != null && chat.name!.isNotEmpty) ? chat.name! : 'Group chat',
        subtitle: previewText,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupChatScreen(groupId: chat.chatId, currentUserId: currentUserId),
          ),
        ),
      );
    }

    // 1:1 chat — name/avatar come from the friend's live profile stream.
    return StreamBuilder<ProfileEntity>(
      stream: _friendProfileStream,
      initialData: _initialCached,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final bool isLiveSnapshot = snapshot.connectionState != ConnectionState.waiting;

        // Keep the disk cache in sync, but only from a real Firestore
        // snapshot — never re-save the seed/initialData back onto itself
        // (same rule as chat_app_bar.dart). saveIfChanged no-ops when
        // nothing actually changed, so this never becomes a redundant write.
        if (profile != null && isLiveSnapshot) {
          FriendProfileCacheService.instance.saveIfChanged(profile);
        }

        final hasAvatar = profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty;
        final displayName = (profile?.displayName != null && profile!.displayName.isNotEmpty)
            ? profile.displayName
            : (!isLiveSnapshot ? 'Loading...' : 'Unknown user');

        return _buildTile(
          context: context,
          unread: unread,
          lastMessageAt: chat.lastMessageAt,
          avatar: PhotoPlaceholder(
            icon: Icons.person_rounded,
            imageUrl: hasAvatar ? profile.avatarUrl : null,
          ),
          title: displayName,
          subtitle: previewText,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(chatId: chat.chatId, currentUserId: currentUserId),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTile({
    required BuildContext context,
    required int unread,
    required DateTime lastMessageAt,
    required Widget avatar,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.small, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Hero(
          tag: 'home-avatar-${widget.chat.chatId}',
          child: ClipOval(
            child: SizedBox(width: 40, height: 40, child: avatar),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatChatListTimestamp(lastMessageAt),
              style: TextStyle(
                fontSize: 11,
                color: unread > 0 ? AppColors.primary : AppColors.textSecondary,
                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            if (unread > 0)
              TweenAnimationBuilder<double>(
                key: ValueKey('unread-$unread'),
                tween: Tween(begin: 0.6, end: 1.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.primary,
                  child: Text('$unread', style: const TextStyle(fontSize: 11, color: Colors.white)),
                ),
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// Top-right profile menu: circular avatar (top-right corner) that opens a
// popup menu with "My Profile" and "Logout". Presentation-layer only —
// reuses the existing ProfileBloc/DI pattern already used by
// MyProfileScreen (see search_screen.dart's `_openProfile`) to read the
// current user's own avatar, reuses the existing MyProfileScreen for
// navigation, and reuses the exact LogoutUseCase + AuthScreen flow already
// implemented in settings_screen.dart's `_confirmLogout`. No new bloc
// events, no new DI registrations, no new packages.
class _ProfileMenuButton extends StatefulWidget {
  final String currentUserId;
  const _ProfileMenuButton({required this.currentUserId});

  @override
  State<_ProfileMenuButton> createState() => _ProfileMenuButtonState();
}

class _ProfileMenuButtonState extends State<_ProfileMenuButton> {
  late final ProfileBloc _profileBloc;

  @override
  void initState() {
    super.initState();
    _profileBloc = di.sl<ProfileBloc>()
      ..add(LoadProfileEvent(uid: widget.currentUserId, viewerUid: widget.currentUserId));
  }

  @override
  void dispose() {
    _profileBloc.close();
    super.dispose();
  }

  void _openMyProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyProfileScreen(uid: widget.currentUserId),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logout')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final result = await di.sl<LogoutUseCase>()();
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthScreen()),
        (route) => false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ProfileBloc>.value(
      value: _profileBloc,
      child: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          String? avatarUrl;
          if (state is ProfileLoadedState) {
            avatarUrl = state.profile.avatarUrl;
          }
          return PopupMenuButton<String>(
            tooltip: 'Profile menu',
            offset: const Offset(0, kToolbarHeight - 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'my_profile') _openMyProfile();
              if (value == 'logout') _confirmLogout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'my_profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('My Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Logout'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipOval(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: PhotoPlaceholder(
                    icon: Icons.person_rounded,
                    iconSize: 18,
                    imageUrl: avatarUrl,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}