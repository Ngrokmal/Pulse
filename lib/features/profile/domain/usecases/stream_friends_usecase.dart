import '../repositories/friend_repository.dart';

class StreamFriendsUseCase {
  final FriendRepository repository;
  const StreamFriendsUseCase(this.repository);

  Stream<List<String>> call(String uid) {
    return repository.streamFriends(uid);
  }
}
