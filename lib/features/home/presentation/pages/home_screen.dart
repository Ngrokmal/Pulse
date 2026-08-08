import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/services/call_notification_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/admin_access.dart';
import '../../../../core/utils/pending_call_navigation.dart';
import '../../../../core/utils/pending_chat_navigation.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../../admin/presentation/pages/admin_dashboard_screen.dart';
import '../../../call/presentation/cubit/incoming_call_listener_cubit.dart';
import '../../../call/presentation/cubit/incoming_call_listener_state.dart';
import '../../../call/presentation/navigation/call_navigator.dart';
import '../blocs/chat_list_bloc.dart';
import '../../../auth/domain/usecases/logout_usecase.dart';
import '../../../auth/presentation/pages/auth_screen.dart';
import '../../../chat/presentation/pages/chat_screen.dart';
import '../../../chat/presentation/pages/create_group_screen.dart';
import '../../../chat/presentation/pages/group_chat_screen.dart';
import '../../../notifications/presentation/blocs/notification_badge_cubit.dart';
import '../../../notifications/presentation/pages/notification_screen.dart';
import '../../../profile/data/datasources/profile_local_data_source.dart';
import '../../../profile/domain/entities/privacy_settings.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/entities/profile_visibility.dart';
import '../../../profile/domain/entities/verification_status.dart';
import '../../../profile/presentation/blocs/profile_bloc.dart';
import '../../../profile/presentation/pages/my_profile_screen.dart';
import '../../../profile/presentation/widgets/photo_placeholder.dart';
import '../../../profile/presentation/widgets/verification_badge.dart';
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
  late final NotificationBadgeCubit _notificationBadgeCubit;
  late final IncomingCallListenerCubit _incomingCallListenerCubit;

  @override
  void initState() {
    super.initState();
    _chatListBloc = di.sl<ChatListBloc>()..add(LoadChatListEvent(widget.currentUserId));
    _notificationBadgeCubit = di.sl<NotificationBadgeCubit>()..start(widget.currentUserId);
    // App-root incoming-call listener (Milestone 3) — same app-wide
    // singleton `.start(uid)` pattern as `_notificationBadgeCubit` above,
    // so a ringing call surfaces regardless of which screen is on top of
    // the navigation stack.
    _incomingCallListenerCubit = di.sl<IncomingCallListenerCubit>()..start(widget.currentUserId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingChatId = PendingChatNavigation.instance.consumePendingChatId();
      if (pendingChatId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(chatId: pendingChatId, currentUserId: widget.currentUserId),
          ),
        );
      }

      // MILESTONE 7: same consume-once pattern as PendingChatNavigation
      // above, for a call notification tapped before this screen (and its
      // IncomingCallListenerCubit) existed to route it — a terminated
      // cold-start tap, most commonly. Routed through the same
      // resolve-then-push path CallNotificationRouter's live-tap
      // handling uses, so the busy/de-dupe guards apply identically here.
      final pendingCallId = PendingCallNavigation.instance.consumePendingCallId();
      if (pendingCallId != null && mounted) {
        unawaited(
          CallNotificationRouter.instance.routeIncomingCall(
            callId: pendingCallId,
            currentUserId: widget.currentUserId,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatListBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<IncomingCallListenerCubit, IncomingCallListenerState>(
      bloc: _incomingCallListenerCubit,
      listener: (context, state) {
        if (state is IncomingCallListenerRinging) {
          CallNavigator.pushIncomingCall(
            session: state.session,
            currentUserId: widget.currentUserId,
            listenerCubit: _incomingCallListenerCubit,
          );
        }
      },
      child: BlocProvider<ChatListBloc>.value(
      value: _chatListBloc,
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
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
            BlocBuilder<NotificationBadgeCubit, int>(
              bloc: _notificationBadgeCubit,
              builder: (context, unreadCount) {
                return IconButton(
                  icon: Badge(
                    label: Text('$unreadCount'),
                    isLabelVisible: unreadCount > 0,
                    backgroundColor: AppColors.error,
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                  tooltip: 'Notifications',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NotificationScreen(currentUserId: widget.currentUserId),
                      ),
                    );
                  },
                );
              },
            ),
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
    ),
    );
  }

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

class _ChatListTile extends StatefulWidget {
  final dynamic chat;
  final String currentUserId;

  const _ChatListTile({super.key, required this.chat, required this.currentUserId});

  @override
  State<_ChatListTile> createState() => _ChatListTileState();
}

class _ChatListTileState extends State<_ChatListTile> {
  // Bug fix (chat tile stale profile): this used to eagerly read the cached
  // profile once here and store it in `_cachedFriend`, so later Hive writes
  // from ProfileBulkWarmupService/ProfileRepositoryImpl were never reflected
  // until the widget was recreated (e.g. app restart). We now only resolve
  // the friend's uid here; the profile itself is read live in build() via a
  // ValueListenableBuilder bound to that uid's Hive key, so the tile
  // rebuilds automatically whenever that specific cache entry changes.
  String? _friendUid;

  @override
  void initState() {
    super.initState();
    if (!widget.chat.isGroup) {
      final friendUid = widget.chat.participantIds.firstWhere(
        (id) => id != widget.currentUserId,
        orElse: () => '',
      );
      if (friendUid.isNotEmpty) {
        _friendUid = friendUid;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final currentUserId = widget.currentUserId;
    final unread = chat.unreadCount[currentUserId] ?? 0;

    final String previewText = chat.lastMessage.isEmpty ? 'No messages yet' : chat.lastMessage;

    if (chat.isGroup) {
      final hasPhoto = chat.groupPhotoUrl != null && chat.groupPhotoUrl!.isNotEmpty;
      return _buildTile(
        context: context,
        unread: unread,
        lastMessageAt: chat.lastMessageAt,
        avatar: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.2),
          backgroundImage: hasPhoto ? ProfileImageCache.instance.providerFor(chat.groupPhotoUrl!) : null,
          onBackgroundImageError: hasPhoto ? (_, __) {} : null,
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

    final friendUid = _friendUid;
    if (friendUid == null) {
      return _buildFriendTile(context, null, unread, previewText);
    }

    // profile_cache is opened during app startup / first profile load; guard
    // defensively so a not-yet-open box can't throw here.
    if (!Hive.isBoxOpen('profile_cache')) {
      return _buildFriendTile(context, ProfileLocalDataSourceImpl.getCachedSync(friendUid), unread, previewText);
    }

    return ValueListenableBuilder<Box<Map>>(
      valueListenable: Hive.box<Map>('profile_cache').listenable(keys: [friendUid]),
      builder: (context, _, __) {
        final profile = ProfileLocalDataSourceImpl.getCachedSync(friendUid);
        return _buildFriendTile(context, profile, unread, previewText);
      },
    );
  }

  Widget _buildFriendTile(BuildContext context, ProfileEntity? profile, int unread, String previewText) {
    final chat = widget.chat;
    final currentUserId = widget.currentUserId;

    final hasAvatar = profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty;
    final displayName = (profile?.displayName != null && profile!.displayName.isNotEmpty)
        ? profile.displayName
        : 'Unknown user';

    final bool showAsOnline = profile != null &&
        profile.isOnline &&
        isVisibleUnder(profile.onlineStatusVisibility, ProfileVisibility.friend);

    return _buildTile(
      context: context,
      unread: unread,
      lastMessageAt: chat.lastMessageAt,
      avatar: PhotoPlaceholder(
        icon: Icons.person_rounded,
        imageUrl: hasAvatar ? profile.avatarUrl : null,
      ),
      title: displayName,
      verificationStatus: profile?.verificationStatus,
      subtitle: showAsOnline ? 'Online' : previewText,
      subtitleColor: showAsOnline ? const Color(0xff2ecc71) : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(chatId: chat.chatId, currentUserId: currentUserId),
        ),
      ),
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
    Color? subtitleColor,
    VerificationStatus? verificationStatus,
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
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (verificationStatus != null) ...[
              const SizedBox(width: 4),
              VerificationBadge(status: verificationStatus, size: 14),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: subtitleColor ?? AppColors.textSecondary, fontSize: 12, fontWeight: subtitleColor != null ? FontWeight.w600 : FontWeight.normal),
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

class _ProfileMenuButton extends StatefulWidget {
  final String currentUserId;
  const _ProfileMenuButton({required this.currentUserId});

  @override
  State<_ProfileMenuButton> createState() => _ProfileMenuButtonState();
}

class _ProfileMenuButtonState extends State<_ProfileMenuButton> {
  late final ProfileBloc _profileBloc;

  // Play Ludo feature: invokes the native Java Ludo King Clone integrated
  // into the Android side of this same app (see MainActivity.kt and
  // android/app/src/ludo/). iOS has no Ludo integration, so this channel
  // is Android-only by construction — the menu item itself is also hidden
  // on non-Android platforms below.
  static const _ludoChannel = MethodChannel('pulse/ludo');

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

  Future<void> _playLudo() async {
    try {
      await _ludoChannel.invokeMethod('startLudo');
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Ludo: ${e.message ?? e.code}')),
      );
    }
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
              if (value == 'play_ludo') _playLudo();
              if (value == 'logout') _confirmLogout();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'my_profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('My Profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // Play Ludo: only wired up on Android (the integrated game
              // is a native Java Android Activity — see MainActivity.kt).
              if (defaultTargetPlatform == TargetPlatform.android)
                const PopupMenuItem(
                  value: 'play_ludo',
                  child: ListTile(
                    leading: Icon(Icons.casino_outlined),
                    title: Text('Play Ludo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
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