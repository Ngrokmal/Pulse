import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/friend_repository.dart';

class GetBlockedUsersUseCase {
  final FriendRepository repository;
  const GetBlockedUsersUseCase(this.repository);

  Future<Either<Failure, List<String>>> call(String uid) {
    return repository.getBlockedUsers(uid);
  }
}
