import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/moderation_guard.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository repository;
  final ModerationGuard moderationGuard;
  const LoginUseCase(this.repository, this.moderationGuard);

  Future<Either<Failure, UserEntity>> call({required String email, required String password}) async {
    final loginResult = await repository.login(email: email, password: password);

    return loginResult.fold(
      (failure) => Left(failure),
      (user) => _enforceModeration(user),
    );
  }

  Future<Either<Failure, UserEntity>> _enforceModeration(UserEntity user) async {
    try {
      await moderationGuard.ensureNotBlocked(user.uid);
      return Right(user);
    } on ModerationBlockedException catch (e) {
      await repository.signOut();
      return Left(ModerationBlockedFailure(e.message));
    }
  }
}
