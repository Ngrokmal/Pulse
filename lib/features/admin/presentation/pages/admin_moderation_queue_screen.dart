import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/admin_guard.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../domain/entities/moderation_report.dart';
import '../../domain/entities/report_status.dart';
import '../../domain/entities/report_type.dart';
import '../cubit/moderation_queue_cubit.dart';
import '../cubit/moderation_queue_state.dart';

class AdminModerationQueueScreen extends StatelessWidget {
  final String adminUid;
  const AdminModerationQueueScreen({super.key, required this.adminUid});

  @override
  Widget build(BuildContext context) {
    return AdminGuard(
      uid: adminUid,
      builder: (context) => BlocProvider<ModerationQueueCubit>(
        create: (_) => di.sl<ModerationQueueCubit>()..load(),
        child: _ModerationQueueView(adminUid: adminUid),
      ),
    );
  }
}

class _ModerationQueueView extends StatelessWidget {
  final String adminUid;
  const _ModerationQueueView({required this.adminUid});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.backgroundBottom,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundBottom,
          title: Text('Moderation Queue', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Reviewed'),
              Tab(text: 'Resolved'),
            ],
          ),
        ),
        body: BlocBuilder<ModerationQueueCubit, ModerationQueueState>(
          builder: (context, state) {
            if (state is ModerationQueueLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is ModerationQueueErrorState) {
              return ErrorStateView(message: state.failure.message);
            }
            if (state is ModerationQueueLoaded) {
              final pending = state.reports.where((r) => r.status == ReportStatus.pending).toList();
              final reviewed = state.reports.where((r) => r.status == ReportStatus.reviewed).toList();
              final resolved = state.reports.where((r) => r.status == ReportStatus.resolved).toList();
              return TabBarView(
                children: [
                  _ReportList(reports: pending, adminUid: adminUid),
                  _ReportList(reports: reviewed, adminUid: adminUid),
                  _ReportList(reports: resolved, adminUid: adminUid),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  final List<ModerationReport> reports;
  final String adminUid;
  const _ReportList({required this.reports, required this.adminUid});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const Center(
        child: Text('No reports', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<ModerationQueueCubit>().load(),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.medium),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.small),
            padding: const EdgeInsets.all(AppSpacing.medium),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel(report.type), style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Reason: ${report.reason}', style: const TextStyle(color: AppColors.textPrimary)),
                if (report.description != null && report.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(report.description!, style: AppTypography.caption),
                ],
                const SizedBox(height: 4),
                Text('Reporter: ${report.reporterUid}', style: AppTypography.caption),
                if (report.targetUid != null) Text('Target: ${report.targetUid}', style: AppTypography.caption),
                if (report.chatId != null) Text('Chat: ${report.chatId}', style: AppTypography.caption),
                if (report.groupId != null) Text('Group: ${report.groupId}', style: AppTypography.caption),
                Text('${report.timestamp}', style: AppTypography.caption),
                const SizedBox(height: AppSpacing.small),
                Wrap(
                  spacing: AppSpacing.small,
                  children: [
                    if (report.status == ReportStatus.pending)
                      TextButton(
                        onPressed: () => context.read<ModerationQueueCubit>().updateStatus(
                              reportId: report.reportId,
                              status: ReportStatus.reviewed,
                              adminUid: adminUid,
                            ),
                        child: const Text('Mark Reviewed'),
                      ),
                    if (report.status != ReportStatus.resolved)
                      TextButton(
                        onPressed: () => context.read<ModerationQueueCubit>().updateStatus(
                              reportId: report.reportId,
                              status: ReportStatus.resolved,
                              adminUid: adminUid,
                            ),
                        child: const Text('Mark Resolved'),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _typeLabel(ReportType type) {
    switch (type) {
      case ReportType.user:
        return 'User Report';
      case ReportType.message:
        return 'Message Report';
      case ReportType.group:
        return 'Group Report';
    }
  }
}
