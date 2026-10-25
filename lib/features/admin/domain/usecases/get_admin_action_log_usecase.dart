import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/admin_action_log_entry.dart';
import '../repositories/admin_repository.dart';

class GetAdminActionLogUseCase {
  final AdminRepository repository;
  const GetAdminActionLogUseCase(this.repository);

  Future<Either<Failure, List<AdminActionLogEntry>>> call() {
    return repository.getActionLog();
  }
}
