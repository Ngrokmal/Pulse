import 'dart:io';

import '../entities/friend_alert_sound_entity.dart';
import '../repositories/friend_alert_sound_repository.dart';

class ReplaceFriendAlertSoundUseCase {
  final FriendAlertSoundRepository repository;
  const ReplaceFriendAlertSoundUseCase(this.repository);

  Future<FriendAlertSoundEntity> call({
    required FriendAlertSoundEntity sound,
    required File audioFile,
    required int durationMs,
  }) {
    return repository.replaceSoundAudio(sound: sound, audioFile: audioFile, durationMs: durationMs);
  }
}
