import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasource/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  const AuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, UserEntity>> login({required String email, required String password}) async {
    try {
      final userModel = await remoteDataSource.loginWithEmailPassword(email, password);
      return Right(userModel);
    } catch (e) {
      return Left(FirebaseFailure(e.toString().replaceFirst('Exception: ', '')));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final userModel = await remoteDataSource.registerWithEmailPassword(
        fullName: fullName,
        username: username,
        email: email,
        password: password,
      );
      return Right(userModel);
    } on UsernameTakenException catch (e) {
      return Left(UsernameTakenFailure(e.message));
    } catch (e) {
      return Left(FirebaseFailure(e.toString().replaceFirst('Exception: ', '')));
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await remoteDataSource.signOut();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }
}
