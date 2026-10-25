import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'moderation_queue_state.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/report_status.dart';
import '../../domain/usecases/get_moderation_reports_usecase.dart';
import '../../domain/usecases/update_report_status_usecase.dart';
import '../../domain/usecases/watch_admin_activity_usecase.dart';

class ModerationQueueCubit extends Cubit<ModerationQueueState> {
  final GetModerationReportsUseCase getModerationReportsUseCase;
  final UpdateReportStatusUseCase updateReportStatusUseCase;
  final WatchAdminActivityUseCase? watchAdminActivityUseCase;

  StreamSubscription<void>? _activitySubscription;

  ModerationQueueCubit({
    required this.getModerationReportsUseCase,
    required this.updateReportStatusUseCase,
    this.watchAdminActivityUseCase,
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

  void startWatching() {
    _activitySubscription?.cancel();
    final useCase = watchAdminActivityUseCase;
    if (useCase == null) return;
    _activitySubscription = useCase().listen((_) {
      final current = state;
      final actionInFlight = current is ModerationQueueLoaded && current.actionInProgress;
      if (!actionInFlight) load();
    });
  }

  @override
  Future<void> close() {
    _activitySubscription?.cancel();
    return super.close();
  }
}
