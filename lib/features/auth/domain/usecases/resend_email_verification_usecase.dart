import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/auth_repository.dart';

class ResendEmailVerificationUseCase {
  final AuthRepository repository;
  const ResendEmailVerificationUseCase(this.repository);

  Future<Either<Failure, void>> call() {
    return repository.resendEmailVerification();
  }
}
