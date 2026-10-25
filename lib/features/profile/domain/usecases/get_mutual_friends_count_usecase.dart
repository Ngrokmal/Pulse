import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/friend_repository.dart';

class GetMutualFriendsCountUseCase {
  final FriendRepository repository;
  const GetMutualFriendsCountUseCase(this.repository);

  Future<Either<Failure, int>> call({required String uid, required String otherUid}) {
    return repository.getMutualFriendsCount(uid: uid, otherUid: otherUid);
  }
}
