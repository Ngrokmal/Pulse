import 'package:flutter_bloc/flutter_bloc.dart';
import 'moderation_queue_state.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/report_status.dart';
import '../../domain/usecases/get_moderation_reports_usecase.dart';
import '../../domain/usecases/update_report_status_usecase.dart';

/// Phase 8.6B (Moderation System)
///
/// Fetches the full 'reports' collection once (same full-scan approach as
/// AdminDashboardCubit) and lets the screen group results into
/// pending/reviewed/resolved tabs client-side — no new queries per tab.
class ModerationQueueCubit extends Cubit<ModerationQueueState> {
  final GetModerationReportsUseCase getModerationReportsUseCase;
  final UpdateReportStatusUseCase updateReportStatusUseCase;

  ModerationQueueCubit({
    required this.getModerationReportsUseCase,
    required this.updateReportStatusUseCase,
  }) : super(ModerationQueueLoading());

  Future<void> load() async {
    emit(ModerationQueueLoading());
    final result = await getModerationReportsUseCase();
    result.fold(
      (failure) => emit(ModerationQueueErrorState(failure)),
      (reports) => emit(ModerationQueueLoaded(reports)),
    );
  }

  Future<void> updateStatus({
    required String reportId,
    required ReportStatus status,
    required String adminUid,
  }) async {
    final current = state;
    if (current is! ModerationQueueLoaded) return;
    emit(ModerationQueueLoaded(current.reports, actionInProgress: true));
    final result = await updateReportStatusUseCase(reportId: reportId, status: status, adminUid: adminUid);
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      emit(ModerationQueueErrorState(failure));
    } else {
      await load();
    }
  }
}
