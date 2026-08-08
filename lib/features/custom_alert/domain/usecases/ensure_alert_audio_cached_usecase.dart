import '../entities/alert_audio_metadata_entity.dart';
import '../repositories/custom_alert_repository.dart';

class EnsureAlertAudioCachedUseCase {
  final CustomAlertRepository repository;
  const EnsureAlertAudioCachedUseCase(this.repository);

  Future<String> call(AlertAudioMetadata metadata) {
    return repository.ensureAudioCached(metadata);
  }
}
