import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/admin_user_record.dart';
import '../repositories/admin_repository.dart';

class LookupUserByUidUseCase {
  final AdminRepository repository;
  const LookupUserByUidUseCase(this.repository);

  Future<Either<Failure, AdminUserRecord?>> call(String uid) {
    return repository.lookupUserByUid(uid);
  }
}
