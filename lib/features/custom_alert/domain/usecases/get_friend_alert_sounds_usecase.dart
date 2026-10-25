import '../entities/friend_alert_sound_entity.dart';
import '../repositories/friend_alert_sound_repository.dart';

class WatchFriendAlertSoundsUseCase {
  final FriendAlertSoundRepository repository;
  const WatchFriendAlertSoundsUseCase(this.repository);

  Stream<List<FriendAlertSoundEntity>> call({
    required String ownerUid,
    required String friendUid,
  }) {
    return repository.watchSoundsForFriend(ownerUid: ownerUid, friendUid: friendUid);
  }
}
