import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/friend_repository.dart';

class GetFriendsUseCase {
  final FriendRepository repository;
  const GetFriendsUseCase(this.repository);

  Future<Either<Failure, List<String>>> call(String uid) {
    return repository.getFriends(uid);
  }
}
