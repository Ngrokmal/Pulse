import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class RegisterUseCase {
  final AuthRepository repository;
  const RegisterUseCase(this.repository);

  Future<Either<Failure, UserEntity>> call({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    return await repository.register(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
    );
  }
}
