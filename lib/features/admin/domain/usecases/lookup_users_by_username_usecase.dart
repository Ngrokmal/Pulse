import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/admin_user_record.dart';
import '../repositories/admin_repository.dart';

class LookupUsersByUsernameUseCase {
  final AdminRepository repository;
  const LookupUsersByUsernameUseCase(this.repository);

  Future<Either<Failure, List<AdminUserRecord>>> call(String query) {
    return repository.lookupUsersByUsername(query);
  }
}
