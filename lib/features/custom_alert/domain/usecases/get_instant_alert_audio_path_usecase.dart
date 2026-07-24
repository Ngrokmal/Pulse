import '../entities/alert_audio_metadata_entity.dart';
import '../repositories/custom_alert_repository.dart';

class GetInstantAlertAudioPathUseCase {
  final CustomAlertRepository repository;
  const GetInstantAlertAudioPathUseCase(this.repository);

  Future<String?> call(AlertAudioMetadata metadata) {
    return repository.getInstantAudioPath(metadata);
  }
}
