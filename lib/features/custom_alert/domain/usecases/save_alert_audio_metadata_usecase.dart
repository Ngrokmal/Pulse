import '../entities/alert_audio_metadata_entity.dart';
import '../repositories/custom_alert_repository.dart';

class SaveAlertAudioMetadataUseCase {
  final CustomAlertRepository repository;
  const SaveAlertAudioMetadataUseCase(this.repository);

  Future<void> call(AlertAudioMetadata metadata) {
    return repository.saveAlertMetadata(metadata);
  }
}
