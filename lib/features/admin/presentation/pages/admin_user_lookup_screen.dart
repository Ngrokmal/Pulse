import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/admin_guard.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../cubit/admin_user_lookup_cubit.dart';
import '../cubit/admin_user_lookup_state.dart';
import 'admin_user_detail_screen.dart';

class AdminUserLookupScreen extends StatelessWidget {
  final String uid;
  const AdminUserLookupScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      uid: uid,
      builder: (context) => BlocProvider<AdminUserLookupCubit>(
        create: (_) => di.sl<AdminUserLookupCubit>(),
        child: _AdminUserLookupView(uid: uid),
      ),
    );
  }
}

class _AdminUserLookupView extends StatefulWidget {
  final String uid;
  const _AdminUserLookupView({required this.uid});

  @override
  State<_AdminUserLookupView> createState() => _AdminUserLookupViewState();
}

class _AdminUserLookupViewState extends State<_AdminUserLookupView> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminUserLookupCubit>();

    return Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundBottom,
        title: Text('User Lookup', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.medium),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by uid or username',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onSubmitted: cubit.search,
            ),
          ),
          Expanded(
            child: BlocBuilder<AdminUserLookupCubit, AdminUserLookupState>(
              builder: (context, state) {
                if (state is AdminUserLookupInitial) {
                  return const EmptyState(
                    icon: Icons.manage_search_outlined,
                    title: 'Search for a user',
                    subtitle: 'Enter a uid or username to look up their account',
                  );
                }
                if (state is AdminUserLookupLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is AdminUserLookupErrorState) {
                  return ErrorStateView(message: state.failure.message);
                }
                if (state is AdminUserLookupLoaded) {
                  if (state.results.isEmpty) {
                    return const EmptyState(icon: Icons.person_off_outlined, title: 'No matching users');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
                    itemCount: state.results.length,
                    itemBuilder: (context, index) {
                      final record = state.results[index];
                      final profile = record.profile;
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.small),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withOpacity(0.2),
                            backgroundImage: (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
                                ? NetworkImage(profile.avatarUrl!)
                                : null,
                            child: (profile.avatarUrl == null || profile.avatarUrl!.isEmpty)
                                ? const Icon(Icons.person, color: AppColors.textPrimary)
                                : null,
                          ),
                          title: Text(profile.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          subtitle: Text('@${profile.username} · ${profile.uid}', style: AppTypography.caption),
                          trailing: (record.isBanned || record.isDisabled)
                              ? const Icon(Icons.block, color: AppColors.error)
                              : const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AdminUserDetailScreen(adminUid: widget.uid, targetUid: profile.uid),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
