import '../entities/friend_alert_sound_entity.dart';
import '../repositories/friend_alert_sound_repository.dart';

class GetFriendAlertSoundsUseCase {
  final FriendAlertSoundRepository repository;
  const GetFriendAlertSoundsUseCase(this.repository);

  Future<List<FriendAlertSoundEntity>> call({
    required String ownerUid,
    required String friendUid,
  }) {
    return repository.getSoundsForFriend(ownerUid: ownerUid, friendUid: friendUid);
  }
}
