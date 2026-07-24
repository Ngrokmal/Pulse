import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user_warning.dart';
import '../repositories/admin_repository.dart';

class GetUserWarningsUseCase {
  final AdminRepository repository;
  const GetUserWarningsUseCase(this.repository);

  Future<Either<Failure, List<UserWarning>>> call(String userUid) {
    return repository.getUserWarnings(userUid);
  }
}
