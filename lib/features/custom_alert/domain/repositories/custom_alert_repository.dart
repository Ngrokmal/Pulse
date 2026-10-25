import '../entities/alert_audio_metadata_entity.dart';

abstract class CustomAlertRepository {
  Future<AlertAudioMetadata?> getAlertMetadata(String alertId);

  Future<void> saveAlertMetadata(AlertAudioMetadata metadata);

  Future<List<AlertAudioMetadata>> getAllAlertMetadata();

  Future<bool> isAudioCached(String alertId);

  Future<String?> getInstantAudioPath(AlertAudioMetadata metadata);

  Future<String> ensureAudioCached(AlertAudioMetadata metadata);

  Future<void> evictAudioCache(String alertId);

  Future<void> clearAllAudioCache();

  Future<int> getAudioCacheSizeBytes();
}
