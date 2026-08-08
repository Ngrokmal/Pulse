import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/ban_record.dart';
import '../repositories/admin_repository.dart';

class GetBanHistoryUseCase {
  final AdminRepository repository;
  const GetBanHistoryUseCase(this.repository);

  Future<Either<Failure, List<BanRecord>>> call(String targetUid) {
    return repository.getBanHistory(targetUid);
  }
}
