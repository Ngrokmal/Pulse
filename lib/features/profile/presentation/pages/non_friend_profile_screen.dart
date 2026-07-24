import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../../core/widgets/report_dialog.dart';
import '../../../admin/domain/usecases/report_user_usecase.dart';
import '../../../chat/domain/usecases/get_or_create_direct_chat_usecase.dart';
import '../../../chat/presentation/pages/chat_screen.dart';
import '../../domain/entities/friend_request_status.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/entities/profile_visibility.dart';
import '../blocs/profile_bloc.dart';
import '../models/profile_ui_data.dart';
import '../widgets/privacy_indicator.dart';
import '../widgets/profile_action_button.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_statistic_card.dart';
import '../widgets/verification_badge.dart';

class NonFriendProfileScreen extends StatelessWidget {
  final String uid;
  final String viewerUid;
  final VoidCallback? onAddFriend;
  final VoidCallback? onMessage;

  const NonFriendProfileScreen({super.key, required this.uid, required this.viewerUid, this.onAddFriend, this.onMessage});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ProfileBloc>()..add(LoadProfileEvent(uid: uid, viewerUid: viewerUid)),
      child: _NonFriendProfileView(viewerUid: viewerUid, onAddFriend: onAddFriend, onMessage: onMessage),
    );
  }
}

class _NonFriendProfileView extends StatelessWidget {
  final String viewerUid;
  final VoidCallback? onAddFriend;
  final VoidCallback? onMessage;

  const _NonFriendProfileView({required this.viewerUid, this.onAddFriend, this.onMessage});

  // Root cause fix (Message button dead-end): mirrors FriendProfileScreen's
  // _openChat. Audited whether non-friends should be messageable at all —
  // neither firestore.rules' chats/{chatId} create rule nor
  // FriendActionAuthorization/FriendSecurityGateway gate messaging on
  // friendship (only profile visibility — bio/media — is friend-gated), so
  // the product's existing backend design already permits it. Reusing the
  // same use case rather than adding a second implementation.
  Future<void> _openChat(BuildContext context, String targetUid) async {
    final chatId = await di.sl<GetOrCreateDirectChatUseCase>()(uidA: viewerUid, uidB: targetUid);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId, currentUserId: viewerUid)),
    );
  }

  Future<void> _reportUser(BuildContext context, String targetUid) async {
    final submission = await showReportDialog(context, title: 'Report User', includeDescription: true);
    if (submission == null) return;
    final result = await di.sl<ReportUserUseCase>()(
      reporterUid: viewerUid,
      targetUid: targetUid,
      reason: submission.reason,
      description: submission.description,
    );
    if (!context.mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted'))),
    );
  }

  List<Widget> _friendActionButtons(BuildContext context, ProfileLoadedState state, String profileUid) {
    final bool isPending = state.isFriendActionPending;
    switch (state.friendRequestStatus) {
      case FriendRequestStatus.notFriends:
        return [
          ProfileActionButton(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Add Friend',
            isPrimary: true,
            onTap: isPending
                ? null
                : onAddFriend ??
                    () => context
                        .read<ProfileBloc>()
                        .add(SendFriendRequestRequested(fromUid: viewerUid, toUid: profileUid)),
          ),
        ];
      case FriendRequestStatus.requestSent:
        return [
          ProfileActionButton(
            icon: Icons.close_rounded,
            label: 'Cancel Request',
            onTap: isPending
                ? null
                : () => context
                    .read<ProfileBloc>()
                    .add(CancelFriendRequestRequested(uid: viewerUid, targetUid: profileUid)),
          ),
        ];
      case FriendRequestStatus.requestReceived:
        return [
          ProfileActionButton(
            icon: Icons.check_rounded,
            label: 'Accept',
            isPrimary: true,
            onTap: isPending
                ? null
                : () => context
                    .read<ProfileBloc>()
                    .add(AcceptFriendRequestRequested(uid: viewerUid, requesterUid: profileUid)),
          ),
          const SizedBox(width: AppSpacing.small),
          ProfileActionButton(
            icon: Icons.close_rounded,
            label: 'Reject',
            isDestructive: true,
            onTap: isPending
                ? null
                : () => context
                    .read<ProfileBloc>()
                    .add(RejectFriendRequestRequested(uid: viewerUid, requesterUid: profileUid)),
          ),
        ];
      case FriendRequestStatus.friends:
        return const [];
    }
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
        ProfileImageCache.instance.precache(context, avatarUrl: data.avatarUrl);
        final bool isBlocked = state.visibility == ProfileVisibility.blocked;
        final bool showOnline = isVisibleUnder(state.profile.onlineStatusVisibility, state.visibility);
        final bool showLastSeen = isVisibleUnder(state.profile.lastSeenVisibility, state.visibility);
        final bool isPrivateProfile = !isBlocked && state.profile.profilePrivacy == PrivacyOption.private;

        return Scaffold(
          backgroundColor: AppColors.backgroundBottom,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.backgroundBottom,
                pinned: true,
                title: Text(data.name, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                actions: [
                  if (!isBlocked)
                    PopupMenuButton<String>(
                      color: AppColors.surface,
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (v) {
                        if (v == 'block') {
                          context.read<ProfileBloc>().add(BlockUserRequested(uid: viewerUid, targetUid: data.uid));
                        } else {
                          _reportUser(context, data.uid);
                        }
                      },
                      itemBuilder: (context) => [
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
                      heroTag: 'nonfriend-${data.username}',
                      name: data.name,
                      username: data.username,
                      bio: null,
                      isOnline: showOnline && data.isOnline,
                      showOnlineStatus: showOnline,
                      lastSeen: showLastSeen ? data.lastSeen : null,
                      avatarUrl: data.avatarUrl,
                      verificationBadge: VerificationBadge(status: data.verificationStatus),
                    ),
                    const SizedBox(height: AppSpacing.large),
                    if (isBlocked)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                        child: Column(
                          children: [
                            const PrivacyIndicator(message: 'You can\'t interact with this account'),
                            const SizedBox(height: AppSpacing.small),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => context
                                    .read<ProfileBloc>()
                                    .add(UnblockUserRequested(uid: viewerUid, targetUid: data.uid)),
                                child: const Text('Unblock'),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                        child: Row(
                          children: [
                            ..._friendActionButtons(context, state, data.uid),
                            const SizedBox(width: AppSpacing.small),
                            ProfileActionButton(
                              icon: Icons.chat_bubble_outline_rounded,
                              label: 'Message',
                              onTap: onMessage ?? () => _openChat(context, data.uid),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.large),
                    if (isPrivateProfile)
                      const PrivacyIndicator(message: 'This account is private. Add them as a friend to see their profile.')
                    else
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
                    const PrivacyIndicator(message: 'Bio, media and more are visible only to friends'),
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
