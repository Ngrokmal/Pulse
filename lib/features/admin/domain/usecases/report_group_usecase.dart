import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/admin_repository.dart';

class ReportGroupUseCase {
  final AdminRepository repository;
  const ReportGroupUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String reporterUid,
    required String groupId,
    required String reason,
  }) {
    return repository.reportGroup(
      reporterUid: reporterUid,
      groupId: groupId,
      reason: reason,
    );
  }
}
