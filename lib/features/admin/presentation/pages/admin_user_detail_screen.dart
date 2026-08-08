import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/admin_guard.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../domain/entities/ban_record.dart';
import '../../domain/entities/ban_status.dart';
import '../../domain/entities/ban_type.dart';
import '../cubit/admin_user_detail_cubit.dart';
import '../cubit/admin_user_detail_state.dart';

class AdminUserDetailScreen extends StatelessWidget {
  final String adminUid;
  final String targetUid;
  const AdminUserDetailScreen({super.key, required this.adminUid, required this.targetUid});

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      uid: adminUid,
      builder: (context) => BlocProvider<AdminUserDetailCubit>(
        create: (_) => di.sl<AdminUserDetailCubit>(param1: targetUid, param2: adminUid)..load(),
        child: const _AdminUserDetailView(),
      ),
    );
  }
}

class _AdminUserDetailView extends StatelessWidget {
  const _AdminUserDetailView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundBottom,
        title: Text('User Detail', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<AdminUserDetailCubit, AdminUserDetailState>(
        builder: (context, state) {
          if (state is AdminUserDetailLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is AdminUserDetailNotFound) {
            return const Center(
              child: Text('No user found for that uid', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          if (state is AdminUserDetailErrorState) {
            return ErrorStateView(message: state.failure.message);
          }
          if (state is AdminUserDetailLoaded) {
            final record = state.record;
            final profile = record.profile;
            final cubit = context.read<AdminUserDetailCubit>();

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.medium),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    backgroundImage: (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
                        ? NetworkImage(profile.avatarUrl!)
                        : null,
                    child: (profile.avatarUrl == null || profile.avatarUrl!.isEmpty)
                        ? const Icon(Icons.person, size: 36, color: AppColors.textPrimary)
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.medium),
                Center(
                  child: Text(profile.displayName, style: AppTypography.title.copyWith(fontSize: 20)),
                ),
                Center(
                  child: Text('@${profile.username}', style: AppTypography.body),
                ),
                const SizedBox(height: AppSpacing.large),
                _InfoTile(label: 'UID', value: profile.uid),
                _InfoTile(label: 'Email', value: profile.email ?? '—'),
                _InfoTile(label: 'Friends', value: '${profile.friendsCount}'),
                _InfoTile(label: 'Groups', value: '${profile.groupsCount}'),
                _InfoTile(
                  label: 'Status',
                  value: record.isBanned
                      ? (record.banType == BanType.temporary ? 'Banned (temporary)' : 'Banned (permanent)')
                      : (record.isDisabled ? 'Disabled' : 'Active'),
                ),
                if (record.isBanned && record.banType == BanType.temporary && record.banExpiresAt != null)
                  _InfoTile(label: 'Ban expires', value: '${record.banExpiresAt}'),
                const SizedBox(height: AppSpacing.large),
                const Text(
                  'Moderation actions',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.small),
                Wrap(
                  spacing: AppSpacing.small,
                  runSpacing: AppSpacing.small,
                  children: [
                    if (!record.isBanned)
                      _ActionButton(
                        label: 'Ban User',
                        icon: Icons.block,
                        enabled: !state.actionInProgress,
                        onPressed: () => _showBanDialog(context, cubit),
                      )
                    else
                      _ActionButton(
                        label: 'Unban User',
                        icon: Icons.check_circle_outline,
                        enabled: !state.actionInProgress,
                        onPressed: cubit.unban,
                      ),
                    if (!record.isDisabled)
                      _ActionButton(
                        label: 'Disable Account',
                        icon: Icons.person_off_outlined,
                        enabled: !state.actionInProgress,
                        onPressed: cubit.disable,
                      )
                    else
                      _ActionButton(
                        label: 'Restore Account',
                        icon: Icons.restore,
                        enabled: !state.actionInProgress,
                        onPressed: cubit.restore,
                      ),
                    _ActionButton(
                      label: 'Issue Warning',
                      icon: Icons.warning_amber_outlined,
                      enabled: !state.actionInProgress,
                      onPressed: () => _showIssueWarningDialog(context, cubit),
                    ),
                  ],
                ),
                if (state.actionInProgress) ...[
                  const SizedBox(height: AppSpacing.medium),
                  const Center(child: CircularProgressIndicator()),
                ],
                const SizedBox(height: AppSpacing.large),
                Text('Warnings (${state.warnings.length})', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.small),
                if (state.warnings.isEmpty)
                  const Text('No warnings issued', style: AppTypography.caption)
                else
                  ...state.warnings.map(
                    (w) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${w.reason} — ${w.timestamp}',
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.large),
                Text('Ban history (${state.banHistory.length})', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.small),
                if (state.banHistory.isEmpty)
                  const Text('No bans on record', style: AppTypography.caption)
                else
                  ...state.banHistory.map((b) => _BanHistoryTile(record: b)),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

void _showBanDialog(BuildContext context, AdminUserDetailCubit cubit) {
  final reasonController = TextEditingController();
  final durationController = TextEditingController();
  BanType selectedType = BanType.permanent;

  showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Ban User', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Reason for ban'),
            ),
            const SizedBox(height: AppSpacing.small),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<BanType>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Permanent', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    value: BanType.permanent,
                    groupValue: selectedType,
                    onChanged: (value) => setState(() => selectedType = value!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<BanType>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Temporary', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    value: BanType.temporary,
                    groupValue: selectedType,
                    onChanged: (value) => setState(() => selectedType = value!),
                  ),
                ),
              ],
            ),
            if (selectedType == BanType.temporary)
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(hintText: 'Duration in days'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              DateTime? expiresAt;
              if (selectedType == BanType.temporary) {
                final days = int.tryParse(durationController.text.trim());
                if (days == null || days <= 0) return;
                expiresAt = DateTime.now().add(Duration(days: days));
              }
              cubit.ban(reason: reason, type: selectedType, expiresAt: expiresAt);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Ban'),
          ),
        ],
      ),
    ),
  );
}

void _showIssueWarningDialog(BuildContext context, AdminUserDetailCubit cubit) {
  final controller = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Issue Warning', style: TextStyle(color: AppColors.textPrimary)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(hintText: 'Reason for warning'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final reason = controller.text.trim();
            if (reason.isEmpty) return;
            cubit.issueWarning(reason);
            Navigator.of(dialogContext).pop();
          },
          child: const Text('Issue'),
        ),
      ],
    ),
  );
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.caption)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionButton({required this.label, required this.icon, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
      ),
    );
  }
}

class _BanHistoryTile extends StatelessWidget {
  final BanRecord record;
  const _BanHistoryTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final isActive = record.status == BanStatus.active && !record.isExpired;
    final typeLabel = record.type == BanType.temporary ? 'Temporary' : 'Permanent';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '[${isActive ? 'Active' : 'Lifted'} · $typeLabel] ${record.reason} — ${record.timestamp}',
        style: const TextStyle(color: AppColors.textPrimary),
      ),
    );
  }
}
