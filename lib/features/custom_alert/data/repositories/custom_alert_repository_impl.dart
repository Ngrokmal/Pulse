import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/repositories/custom_alert_repository.dart';
import '../datasources/alert_audio_metadata_local_data_source.dart';
import '../services/audio_cache_manager.dart';
import '../services/audio_download_manager.dart';
import '../services/audio_validation_service.dart';

class CustomAlertRepositoryImpl implements CustomAlertRepository {
  final AlertAudioMetadataLocalDataSource metadataLocalDataSource;
  final AudioCacheManager cacheManager;
  final AudioDownloadManager downloadManager;
  final AudioValidationService validationService;

  const CustomAlertRepositoryImpl({
    required this.metadataLocalDataSource,
    required this.cacheManager,
    required this.downloadManager,
    required this.validationService,
  });

  @override
  Future<AlertAudioMetadata?> getAlertMetadata(String alertId) async {
    try {
      return metadataLocalDataSource.getMetadata(alertId);
    } catch (e) {
      throw CacheException(message: 'Failed to read alert metadata: $e');
    }
  }

  @override
  Future<void> saveAlertMetadata(AlertAudioMetadata metadata) async {
    validationService.validateMetadata(metadata);
    try {
      await metadataLocalDataSource.saveMetadata(metadata);
    } catch (e) {
      throw CacheException(message: 'Failed to save alert metadata: $e');
    }
  }

  @override
  Future<List<AlertAudioMetadata>> getAllAlertMetadata() async {
    try {
      return metadataLocalDataSource.getAllMetadata();
    } catch (e) {
      throw CacheException(message: 'Failed to read alert metadata list: $e');
    }
  }

  @override
  Future<bool> isAudioCached(String alertId) {
    return cacheManager.isCached(alertId);
  }

  @override
  Future<String?> getInstantAudioPath(AlertAudioMetadata metadata) async {
    try {
      final isValid = await cacheManager.validateCachedFile(
        alertId: metadata.alertId,
        expectedChecksum: metadata.checksum,
      );
      if (!isValid) return null;
      final cachedFile = await cacheManager.getCachedFile(metadata.alertId);
      return cachedFile?.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> ensureAudioCached(AlertAudioMetadata metadata) async {
    validationService.validateMetadata(metadata);

    final alreadyValid = await cacheManager.validateCachedFile(
      alertId: metadata.alertId,
      expectedChecksum: metadata.checksum,
    );
    if (alreadyValid) {
      final cachedFile = await cacheManager.getCachedFile(metadata.alertId);
      if (cachedFile != null) {
        return cachedFile.path;
      }
    }

    final bytes = await downloadManager.download(metadata.audioUrl);
    validationService.validateDownloadedBytes(bytes, metadata);

    final storedFile = await cacheManager.store(
      alertId: metadata.alertId,
      bytes: bytes,
      expectedChecksum: metadata.checksum,
    );

    try {
      await metadataLocalDataSource.saveMetadata(metadata);
    } catch (e) {
      throw CacheException(message: 'Failed to persist alert metadata after caching: $e');
    }

    return storedFile.path;
  }

  @override
  Future<void> evictAudioCache(String alertId) {
    return cacheManager.evict(alertId);
  }

  @override
  Future<void> clearAllAudioCache() {
    return cacheManager.clearAll();
  }

  @override
  Future<int> getAudioCacheSizeBytes() {
    return cacheManager.getCacheSizeBytes();
  }
}
