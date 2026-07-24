import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';

class AudioValidationService {
  const AudioValidationService();

  static const Set<String> allowedFormats = {'mp3', 'aac', 'wav', 'm4a', 'ogg'};
  static const int maxFileSizeBytes = 2 * 1024 * 1024;

  void validateMetadata(AlertAudioMetadata metadata) {
    if (metadata.alertId.isEmpty) {
      throw ServerException(message: 'Alert audio metadata missing alertId');
    }

    final uri = Uri.tryParse(metadata.audioUrl);
    if (uri == null || !uri.isScheme('HTTPS')) {
      throw ServerException(message: 'Alert audio metadata has an invalid audioUrl');
    }

    if (!allowedFormats.contains(metadata.format.toLowerCase())) {
      throw ServerException(message: 'Unsupported alert audio format: ${metadata.format}');
    }

    if (metadata.fileSizeBytes <= 0 || metadata.fileSizeBytes > maxFileSizeBytes) {
      throw ServerException(message: 'Alert audio file size out of allowed range');
    }

    if (metadata.checksum.isEmpty) {
      throw ServerException(message: 'Alert audio metadata missing checksum');
    }
  }

  void validateDownloadedBytes(List<int> bytes, AlertAudioMetadata metadata) {
    if (bytes.isEmpty) {
      throw CacheException(message: 'Downloaded alert audio for ${metadata.alertId} is empty');
    }
    if (bytes.length != metadata.fileSizeBytes) {
      throw CacheException(message: 'Downloaded alert audio size mismatch for ${metadata.alertId}');
    }
  }
}
