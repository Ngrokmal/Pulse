import 'dart:io';

import '../entities/friend_alert_sound_entity.dart';
import '../repositories/friend_alert_sound_repository.dart';

class CreateFriendAlertSoundUseCase {
  final FriendAlertSoundRepository repository;
  const CreateFriendAlertSoundUseCase(this.repository);

  Future<FriendAlertSoundEntity> call({
    required String ownerUid,
    required File audioFile,
    required String displayName,
    required int durationMs,
    String? friendUid,
  }) {
    return repository.createSound(
      ownerUid: ownerUid,
      audioFile: audioFile,
      displayName: displayName,
      durationMs: durationMs,
      friendUid: friendUid,
    );
  }
}
