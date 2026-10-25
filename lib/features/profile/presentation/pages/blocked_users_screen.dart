import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/usecases/stream_profile_usecase.dart';
import '../blocs/profile_bloc.dart';
import '../widgets/photo_placeholder.dart';

class BlockedUsersScreen extends StatefulWidget {
  final String uid;

  const BlockedUsersScreen({super.key, required this.uid});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ProfileBloc>().add(LoadBlockedUsersRequested(uid: widget.uid));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundBottom,
        title: Text('Blocked Users', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is! ProfileLoadedState || state.blockedUserIds == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final blockedIds = state.blockedUserIds!;
          if (blockedIds.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.large),
                child: Text('No blocked users', style: AppTypography.body),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.medium),
            itemCount: blockedIds.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.small),
            itemBuilder: (context, index) => _BlockedUserTile(
              uid: widget.uid,
              targetUid: blockedIds[index],
            ),
          );
        },
      ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  final String uid;
  final String targetUid;

  const _BlockedUserTile({required this.uid, required this.targetUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProfileEntity>(
      stream: di.sl<StreamProfileUseCase>()(targetUid),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name = profile?.displayName.isNotEmpty == true ? profile!.displayName : (profile?.username ?? targetUid);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(width: 44, height: 44, child: PhotoPlaceholder(iconSize: 20, imageUrl: profile?.avatarUrl)),
              ),
              const SizedBox(width: AppSpacing.medium),
              Expanded(
                child: Text(name, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
              ),
              TextButton(
                onPressed: () => context.read<ProfileBloc>().add(UnblockUserFromSettingsRequested(uid: uid, targetUid: targetUid)),
                child: const Text('Unblock'),
              ),
            ],
          ),
        );
      },
    );
  }
}
