import '../entities/friend_alert_sound_entity.dart';
import '../repositories/friend_alert_sound_repository.dart';

class RenameFriendAlertSoundUseCase {
  final FriendAlertSoundRepository repository;
  const RenameFriendAlertSoundUseCase(this.repository);

  Future<FriendAlertSoundEntity> call({
    required FriendAlertSoundEntity sound,
    required String newDisplayName,
  }) {
    return repository.renameSound(sound: sound, newDisplayName: newDisplayName);
  }
}
