import '../entities/alert_audio_metadata_entity.dart';
import '../repositories/custom_alert_repository.dart';

class GetAlertAudioMetadataUseCase {
  final CustomAlertRepository repository;
  const GetAlertAudioMetadataUseCase(this.repository);

  Future<AlertAudioMetadata?> call(String alertId) {
    return repository.getAlertMetadata(alertId);
  }
}
