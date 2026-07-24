import '../entities/friend_alert_sound_entity.dart';
import '../repositories/friend_alert_sound_repository.dart';

class DeleteFriendAlertSoundUseCase {
  final FriendAlertSoundRepository repository;
  const DeleteFriendAlertSoundUseCase(this.repository);

  Future<void> call(FriendAlertSoundEntity sound) {
    return repository.deleteSound(sound);
  }
}
