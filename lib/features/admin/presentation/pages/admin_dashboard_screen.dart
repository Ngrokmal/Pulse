import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/admin_guard.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../cubit/admin_dashboard_cubit.dart';
import '../cubit/admin_dashboard_state.dart';
import 'admin_moderation_queue_screen.dart';
import 'admin_user_lookup_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  final String uid;
  const AdminDashboardScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      uid: uid,
      builder: (context) => BlocProvider<AdminDashboardCubit>(
        create: (_) => di.sl<AdminDashboardCubit>()..load(),
        child: _AdminDashboardView(uid: uid),
      ),
    );
  }
}

class _AdminDashboardView extends StatelessWidget {
  final String uid;
  const _AdminDashboardView({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundBottom,
        title: Text('Admin', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Moderation queue',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminModerationQueueScreen(adminUid: uid)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: 'User lookup',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminUserLookupScreen(uid: uid)),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<AdminDashboardCubit, AdminDashboardState>(
        builder: (context, state) {
          if (state is AdminDashboardLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AdminDashboardErrorState) {
            return ErrorStateView(message: state.failure.message);
          }
          if (state is AdminDashboardLoaded) {
            final stats = state.stats;
            return RefreshIndicator(
              onRefresh: () => context.read<AdminDashboardCubit>().load(),
              child: GridView.count(
                padding: const EdgeInsets.all(AppSpacing.medium),
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.medium,
                mainAxisSpacing: AppSpacing.medium,
                childAspectRatio: 1.3,
                children: [
                  _StatCard(label: 'Total Users', value: stats.totalUsers, icon: Icons.people_alt_outlined),
                  _StatCard(label: 'Total Friends', value: stats.totalFriends, icon: Icons.favorite_outline),
                  _StatCard(label: 'Total Chats', value: stats.totalChats, icon: Icons.chat_bubble_outline),
                  _StatCard(label: 'Total Groups', value: stats.totalGroups, icon: Icons.groups_outlined),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.medium),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primaryAccent, size: 26),
          const SizedBox(height: AppSpacing.small),
          Text(
            '$value',
            style: AppTypography.title.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}
