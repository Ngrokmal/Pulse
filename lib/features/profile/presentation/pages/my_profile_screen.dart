import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../blocs/profile_bloc.dart';
import '../models/profile_ui_data.dart';
import '../widgets/about_card.dart';
import '../widgets/empty_media_state.dart';
import '../widgets/media_preview_card.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_photo_flow.dart';
import '../widgets/profile_statistic_card.dart';
import '../widgets/upload_status_banner.dart';
import '../widgets/verification_badge.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';

class MyProfileScreen extends StatelessWidget {
  final String uid;

  const MyProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ProfileBloc>()..add(LoadProfileEvent(uid: uid, viewerUid: uid)),
      child: _MyProfileView(uid: uid),
    );
  }
}

class _MyProfileView extends StatelessWidget {
  final String uid;
  const _MyProfileView({required this.uid});

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

        final data = ProfileUiData.fromEntity(state.profile);
        ProfileImageCache.instance.precache(context, avatarUrl: data.avatarUrl, coverUrl: data.coverUrl);

        return _MyProfileContent(
          uid: uid,
          data: data,
          avatarUpload: state.avatarUpload,
          coverUpload: state.coverUpload,
        );
      },
    );
  }
}

class _MyProfileContent extends StatelessWidget {
  final String uid;
  final ProfileUiData data;
  final PhotoUploadStatus avatarUpload;
  final PhotoUploadStatus coverUpload;

  const _MyProfileContent({
    required this.uid,
    required this.data,
    required this.avatarUpload,
    required this.coverUpload,
  });

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ProfileBloc>();

    return Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.backgroundBottom,
            pinned: true,
            title: Text('My Profile', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(value: bloc, child: SettingsScreen(uid: uid)),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Profile',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(value: bloc, child: EditProfileScreen(uid: uid, data: data)),
                  ),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              children: [
                ProfileHeader(
                  heroTag: 'my-profile',
                  name: data.name,
                  username: data.username,
                  bio: data.bio,
                  isOnline: data.isOnline,
                  avatarUrl: data.avatarUrl,
                  coverUrl: data.coverUrl,
                  verificationBadge: VerificationBadge(status: data.verificationStatus),
                  editable: true,
                  onAvatarTap: () => ProfilePhotoFlow.start(
                    context,
                    title: 'Profile Photo',
                    isCircle: true,
                    hasExistingPhoto: data.avatarUrl != null,
                    currentImageUrl: data.avatarUrl,
                    onPhotoSelected: (File file) => bloc.add(UpdatePhotoRequested(uid: uid, slot: PhotoSlot.avatar, file: file)),
                    onRemove: () => bloc.add(RemovePhotoRequested(uid: uid, slot: PhotoSlot.avatar)),
                  ),
                  onCoverTap: () => ProfilePhotoFlow.start(
                    context,
                    title: 'Cover Photo',
                    isCircle: false,
                    hasExistingPhoto: data.coverUrl != null,
                    currentImageUrl: data.coverUrl,
                    onPhotoSelected: (File file) => bloc.add(UpdatePhotoRequested(uid: uid, slot: PhotoSlot.cover, file: file)),
                    onRemove: () => bloc.add(RemovePhotoRequested(uid: uid, slot: PhotoSlot.cover)),
                  ),
                ),
                UploadStatusBanner(
                  label: 'Profile photo',
                  status: avatarUpload,
                  onRetry: () => bloc.add(RetryPhotoUploadRequested(uid: uid, slot: PhotoSlot.avatar)),
                  onCancel: () => bloc.add(CancelPhotoUploadRequested(slot: PhotoSlot.avatar)),
                ),
                UploadStatusBanner(
                  label: 'Cover photo',
                  status: coverUpload,
                  onRetry: () => bloc.add(RetryPhotoUploadRequested(uid: uid, slot: PhotoSlot.cover)),
                  onCancel: () => bloc.add(CancelPhotoUploadRequested(slot: PhotoSlot.cover)),
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
                        child: ProfileStatisticCard(icon: Icons.groups_rounded, value: '${data.sharedGroupsCount}', label: 'Groups'),
                      ),
                      const SizedBox(width: AppSpacing.small),
                      Expanded(
                        child: ProfileStatisticCard(icon: Icons.perm_media_rounded, value: '${data.mediaCount}', label: 'Media'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.large),
                AboutCard(
                  rows: [
                    if (data.location != null) AboutCardRow(icon: Icons.location_on_outlined, label: 'Location', value: data.location!),
                    if (data.joinDate != null)
                      AboutCardRow(icon: Icons.calendar_today_outlined, label: 'Joined', value: _formatJoinDate(data.joinDate!)),
                  ],
                ),
                const SizedBox(height: AppSpacing.large),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                  child: Row(
                    children: [
                      Text('Media', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${data.mediaCount}', style: AppTypography.caption),
                    ],
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatJoinDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.year}';
  }
}
