import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../chat/domain/usecases/get_or_create_direct_chat_usecase.dart';
import '../../../chat/presentation/pages/chat_screen.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/entities/profile_visibility.dart';
import '../blocs/profile_bloc.dart';
import '../models/profile_ui_data.dart';
import '../widgets/about_card.dart';
import '../widgets/empty_media_state.dart';
import '../widgets/media_preview_card.dart';
import '../widgets/profile_action_button.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_statistic_card.dart';
import '../widgets/verification_badge.dart';

class FriendProfileScreen extends StatelessWidget {
  final String uid;
  final String viewerUid;
  final VoidCallback? onMessage;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;

  const FriendProfileScreen({
    super.key,
    required this.uid,
    required this.viewerUid,
    this.onMessage,
    this.onAudioCall,
    this.onVideoCall,
    this.onBlock,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ProfileBloc>()..add(LoadProfileEvent(uid: uid, viewerUid: viewerUid)),
      child: _FriendProfileView(viewerUid: viewerUid, onMessage: onMessage, onAudioCall: onAudioCall, onVideoCall: onVideoCall, onBlock: onBlock, onReport: onReport),
    );
  }
}

class _FriendProfileView extends StatelessWidget {
  final String viewerUid;
  final VoidCallback? onMessage;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;

  const _FriendProfileView({required this.viewerUid, this.onMessage, this.onAudioCall, this.onVideoCall, this.onBlock, this.onReport});

  void _placeholder(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  // Root cause fix (Message button): previously this always fell through to
  // _placeholder('Open chat') because no chatId was ever resolved/created for
  // a 1:1 conversation anywhere in the app. This creates the chat on first
  // contact (idempotent) or reuses the existing one, then navigates directly
  // — no extra "Open Chat" step.
  Future<void> _openChat(BuildContext context, String targetUid) async {
    final chatId = await di.sl<GetOrCreateDirectChatUseCase>()(uidA: viewerUid, uidB: targetUid);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, currentUserId: viewerUid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is ProfileErrorState) {
          return Scaffold(
            backgroundColor: AppColors.backgroundBottom,
            body: Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.large), child: Text(state.message, textAlign: TextAlign.center))),
          );
        }
        if (state is! ProfileLoadedState) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final data = ProfileUiData.fromEntity(
          state.profile,
          sharedGroupsCountOverride: state.mutualGroupsCount,
          mutualFriendsCountOverride: state.mutualFriendsCount,
        );
        ProfileImageCache.instance.precache(context, avatarUrl: data.avatarUrl, coverUrl: data.coverUrl);
        final bool isBlocked = state.visibility == ProfileVisibility.blocked;
        final bool showOnline = isVisibleUnder(state.profile.onlineStatusVisibility, state.visibility);
        final bool showLastSeen = isVisibleUnder(state.profile.lastSeenVisibility, state.visibility);

        return Scaffold(
          backgroundColor: AppColors.backgroundBottom,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.backgroundBottom,
                pinned: true,
                title: Text(data.name, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                actions: [
                  PopupMenuButton<String>(
                    color: AppColors.surface,
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'unfriend':
                          context.read<ProfileBloc>().add(UnfriendRequested(uid: viewerUid, targetUid: data.uid));
                          break;
                        case 'block':
                          if (onBlock != null) {
                            onBlock!.call();
                          } else {
                            context.read<ProfileBloc>().add(BlockUserRequested(uid: viewerUid, targetUid: data.uid));
                          }
                          break;
                        case 'report':
                          if (onReport != null) {
                            onReport!.call();
                          } else {
                            _placeholder(context, 'Report');
                          }
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'unfriend', child: Text('Unfriend')),
                      const PopupMenuItem(value: 'block', child: Text('Block')),
                      const PopupMenuItem(value: 'report', child: Text('Report')),
                    ],
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    ProfileHeader(
                      heroTag: 'friend-${data.username}',
                      name: data.name,
                      username: data.username,
                      bio: data.bio,
                      isOnline: showOnline && data.isOnline,
                      showOnlineStatus: showOnline,
                      lastSeen: showLastSeen ? data.lastSeen : null,
                      avatarUrl: data.avatarUrl,
                      coverUrl: data.coverUrl,
                      verificationBadge: VerificationBadge(status: data.verificationStatus),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    if (isBlocked)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                        child: _BlockedNotice(
                          onUnblock: () => context.read<ProfileBloc>().add(UnblockUserRequested(uid: viewerUid, targetUid: data.uid)),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                        child: Row(
                          children: [
                            ProfileActionButton(
                              icon: Icons.chat_bubble_rounded,
                              label: 'Message',
                              isPrimary: true,
                              onTap: onMessage ?? () => _openChat(context, data.uid),
                            ),
                            const SizedBox(width: AppSpacing.small),
                            ProfileActionButton(
                              icon: Icons.call_rounded,
                              label: 'Audio Call',
                              onTap: onAudioCall ?? () => _placeholder(context, 'Start audio call'),
                            ),
                            const SizedBox(width: AppSpacing.small),
                            ProfileActionButton(
                              icon: Icons.videocam_rounded,
                              label: 'Video Call',
                              onTap: onVideoCall ?? () => _placeholder(context, 'Start video call'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.small),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                      child: Row(
                        children: [
                          ProfileActionButton(
                            icon: Icons.block_rounded,
                            label: 'Block',
                            isDestructive: true,
                            onTap: onBlock ??
                                () => context.read<ProfileBloc>().add(BlockUserRequested(uid: viewerUid, targetUid: data.uid)),
                          ),
                          const SizedBox(width: AppSpacing.small),
                          ProfileActionButton(
                            icon: Icons.flag_rounded,
                            label: 'Report',
                            isDestructive: true,
                            onTap: onReport ?? () => _placeholder(context, 'Report'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                      child: Row(
                        children: [
                          Expanded(
                            child: ProfileStatisticCard(icon: Icons.people_alt_rounded, value: '${data.mutualFriendsCount}', label: 'Friends'),
                          ),
                          const SizedBox(width: AppSpacing.small),
                          Expanded(
                            child: ProfileStatisticCard(icon: Icons.groups_rounded, value: '${data.sharedGroupsCount}', label: 'Mutual Groups'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    AboutCard(
                      title: 'About',
                      rows: [
                        if (data.location != null) AboutCardRow(icon: Icons.location_on_outlined, label: 'Location', value: data.location!),
                        if (data.joinDate != null)
                          AboutCardRow(icon: Icons.calendar_today_outlined, label: 'Joined', value: '${data.joinDate!.year}'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.large),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Media', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),
                    data.mediaCount == 0
                        ? const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.large), child: EmptyMediaState())
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                            child: GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 6,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: AppSpacing.small,
                                mainAxisSpacing: AppSpacing.small,
                              ),
                              itemBuilder: (context, i) => const MediaPreviewCard(),
                            ),
                          ),
                    const SizedBox(height: AppSpacing.large),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Shared Files', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.small),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.medium),
                      child: EmptyMediaState(title: 'No shared files', subtitle: 'Files you send each other will appear here.'),
                    ),
                    const SizedBox(height: AppSpacing.large),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BlockedNotice extends StatelessWidget {
  final VoidCallback onUnblock;
  const _BlockedNotice({required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.medium),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.block_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: AppSpacing.small),
              const Expanded(child: Text('You can\'t message or call this account.')),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onUnblock, child: const Text('Unblock')),
          ),
        ],
      ),
    );
  }
}
