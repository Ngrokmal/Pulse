import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/moderation_report.dart';
import '../repositories/admin_repository.dart';

class GetModerationReportsUseCase {
  final AdminRepository repository;
  const GetModerationReportsUseCase(this.repository);

  Future<Either<Failure, List<ModerationReport>>> call() {
    return repository.getModerationReports();
  }
}
