import '../../../../core/services/local_db_service.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../models/friend_alert_sound_model.dart';

abstract class AlertSoundLocalDataSource {
  Future<List<FriendAlertSoundEntity>> getCachedSounds(String ownerUid);

  Future<void> upsertSounds(String ownerUid, List<FriendAlertSoundEntity> sounds);

  Future<void> deleteCachedSound(String ownerUid, String alertId);

  Future<DateTime?> getSyncedAt(String ownerUid);

  Future<void> setSyncedAt(String ownerUid, DateTime time);
}

class AlertSoundLocalDataSourceImpl implements AlertSoundLocalDataSource {
  @override
  Future<List<FriendAlertSoundEntity>> getCachedSounds(String ownerUid) async {
    final box = await LocalDbService.alertSoundsBox(ownerUid);
    return box.values.map((raw) => FriendAlertSoundModel.fromCacheJson(Map<String, dynamic>.from(raw))).toList();
  }

  @override
  Future<void> upsertSounds(String ownerUid, List<FriendAlertSoundEntity> sounds) async {
    if (sounds.isEmpty) return;
    final box = await LocalDbService.alertSoundsBox(ownerUid);
    for (final sound in sounds) {
      final model = sound is FriendAlertSoundModel ? sound : FriendAlertSoundModel.fromEntity(sound);
      await box.put(model.alertId, model.toCacheJson());
    }
  }

  @override
  Future<void> deleteCachedSound(String ownerUid, String alertId) async {
    final box = await LocalDbService.alertSoundsBox(ownerUid);
    await box.delete(alertId);
  }

  @override
  Future<DateTime?> getSyncedAt(String ownerUid) {
    return SyncEngine.instance.getCursor('alertSoundsSyncedAt_$ownerUid');
  }

  @override
  Future<void> setSyncedAt(String ownerUid, DateTime time) {
    return SyncEngine.instance.setCursor('alertSoundsSyncedAt_$ownerUid', time);
  }
}
