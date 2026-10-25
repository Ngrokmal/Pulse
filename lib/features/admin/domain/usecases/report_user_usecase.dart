import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/admin_repository.dart';

class ReportUserUseCase {
  final AdminRepository repository;
  const ReportUserUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String reporterUid,
    required String targetUid,
    required String reason,
    String? description,
  }) {
    return repository.reportUser(
      reporterUid: reporterUid,
      targetUid: targetUid,
      reason: reason,
      description: description,
    );
  }
}
