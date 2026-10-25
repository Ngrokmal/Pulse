import '../../../../core/errors/failures.dart';
import '../../domain/entities/admin_dashboard_stats.dart';

abstract class AdminDashboardState {
  const AdminDashboardState();
}

class AdminDashboardLoading extends AdminDashboardState {}

class AdminDashboardLoaded extends AdminDashboardState {
  final AdminDashboardStats stats;
  const AdminDashboardLoaded(this.stats);
}

class AdminDashboardErrorState extends AdminDashboardState {
  final Failure failure;
  const AdminDashboardErrorState(this.failure);
}
