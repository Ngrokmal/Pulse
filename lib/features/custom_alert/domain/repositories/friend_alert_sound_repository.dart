import 'dart:io';

import '../entities/friend_alert_sound_entity.dart';

abstract class FriendAlertSoundRepository {
  Stream<List<FriendAlertSoundEntity>> watchSoundsForFriend({
    required String ownerUid,
    required String friendUid,
  });

  Future<FriendAlertSoundEntity> createSound({
    required String ownerUid,
    required File audioFile,
    required String displayName,
    required int durationMs,
    String? friendUid,
  });

  Future<FriendAlertSoundEntity> renameSound({
    required FriendAlertSoundEntity sound,
    required String newDisplayName,
  });

  Future<FriendAlertSoundEntity> replaceSoundAudio({
    required FriendAlertSoundEntity sound,
    required File audioFile,
    required int durationMs,
  });

  Future<void> deleteSound(FriendAlertSoundEntity sound);
}
