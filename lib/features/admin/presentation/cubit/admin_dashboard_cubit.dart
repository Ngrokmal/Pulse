import 'package:flutter_bloc/flutter_bloc.dart';
import 'admin_dashboard_state.dart';
import '../../domain/usecases/get_admin_dashboard_stats_usecase.dart';

class AdminDashboardCubit extends Cubit<AdminDashboardState> {
  final GetAdminDashboardStatsUseCase getAdminDashboardStatsUseCase;

  AdminDashboardCubit({required this.getAdminDashboardStatsUseCase}) : super(AdminDashboardLoading());

  Future<void> load() async {
    emit(AdminDashboardLoading());
    final result = await getAdminDashboardStatsUseCase();
    result.fold(
      (failure) => emit(AdminDashboardErrorState(failure)),
      (stats) => emit(AdminDashboardLoaded(stats)),
    );
  }
}
