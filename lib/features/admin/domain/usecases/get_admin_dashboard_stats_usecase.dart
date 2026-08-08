import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/admin_dashboard_stats.dart';
import '../repositories/admin_repository.dart';

class GetAdminDashboardStatsUseCase {
  final AdminRepository repository;
  const GetAdminDashboardStatsUseCase(this.repository);

  Future<Either<Failure, AdminDashboardStats>> call() {
    return repository.getDashboardStats();
  }
}
