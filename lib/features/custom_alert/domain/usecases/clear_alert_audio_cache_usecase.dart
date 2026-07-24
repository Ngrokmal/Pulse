import '../repositories/custom_alert_repository.dart';

class ClearAlertAudioCacheUseCase {
  final CustomAlertRepository repository;
  const ClearAlertAudioCacheUseCase(this.repository);

  Future<void> call({String? alertId}) {
    if (alertId != null) {
      return repository.evictAudioCache(alertId);
    }
    return repository.clearAllAudioCache();
  }
}
