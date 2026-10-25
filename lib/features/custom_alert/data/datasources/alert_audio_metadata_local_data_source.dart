import '../../domain/entities/alert_audio_metadata_entity.dart';

abstract class AlertAudioMetadataLocalDataSource {
  Future<void> saveMetadata(AlertAudioMetadata metadata);
  AlertAudioMetadata? getMetadata(String alertId);
  List<AlertAudioMetadata> getAllMetadata();
  Future<void> deleteMetadata(String alertId);
  Future<void> clear();
}

class AlertAudioMetadataLocalDataSourceImpl implements AlertAudioMetadataLocalDataSource {
  final Map<String, AlertAudioMetadata> _localMemoryStorage = {};

  @override
  Future<void> saveMetadata(AlertAudioMetadata metadata) async {
    _localMemoryStorage[metadata.alertId] = metadata;
  }

  @override
  AlertAudioMetadata? getMetadata(String alertId) {
    return _localMemoryStorage[alertId];
  }

  @override
  List<AlertAudioMetadata> getAllMetadata() {
    return _localMemoryStorage.values.toList(growable: false);
  }

  @override
  Future<void> deleteMetadata(String alertId) async {
    _localMemoryStorage.remove(alertId);
  }

  @override
  Future<void> clear() async {
    _localMemoryStorage.clear();
  }
}
