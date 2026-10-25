import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'admin_dashboard_state.dart';
import '../../domain/usecases/get_admin_dashboard_stats_usecase.dart';
import '../../domain/usecases/watch_admin_activity_usecase.dart';

class AdminDashboardCubit extends Cubit<AdminDashboardState> {
  final GetAdminDashboardStatsUseCase getAdminDashboardStatsUseCase;
  final WatchAdminActivityUseCase? watchAdminActivityUseCase;

  StreamSubscription<void>? _activitySubscription;

  AdminDashboardCubit({
    required this.getAdminDashboardStatsUseCase,
    this.watchAdminActivityUseCase,
  }) : super(AdminDashboardLoading());

  Future<void> load() async {
    emit(AdminDashboardLoading());
    final result = await getAdminDashboardStatsUseCase();
    result.fold(
      (failure) => emit(AdminDashboardErrorState(failure)),
      (stats) => emit(AdminDashboardLoaded(stats)),
    );
  }

  void startWatching() {
    _activitySubscription?.cancel();
    final useCase = watchAdminActivityUseCase;
    if (useCase == null) return;
    _activitySubscription = useCase().listen((_) => load());
  }

  @override
  Future<void> close() {
    _activitySubscription?.cancel();
    return super.close();
  }
}
