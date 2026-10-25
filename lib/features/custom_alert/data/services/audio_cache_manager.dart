import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../../../core/errors/exceptions.dart';

class AudioCacheManager {
  AudioCacheManager._privateConstructor();
  static final AudioCacheManager instance = AudioCacheManager._privateConstructor();

  static const String _cacheFolderName = 'pulse_alert_audio_cache';

  Directory? _cacheDirectory;

  Future<Directory> _resolveCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) return existing;
    try {
      final dir = Directory('${Directory.systemTemp.path}/$_cacheFolderName');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDirectory = dir;
      return dir;
    } on FileSystemException catch (e) {
      throw CacheException(message: 'Failed to resolve alert audio cache directory: ${e.message}');
    }
  }

  Future<File> _fileFor(String alertId) async {
    final dir = await _resolveCacheDirectory();
    return File('${dir.path}/$alertId.audio');
  }

  Future<bool> isCached(String alertId) async {
    final file = await _fileFor(alertId);
    return file.exists();
  }

  Future<File?> getCachedFile(String alertId) async {
    final file = await _fileFor(alertId);
    if (await file.exists()) return file;
    return null;
  }

  Future<File> store({
    required String alertId,
    required List<int> bytes,
    required String expectedChecksum,
  }) async {
    final actualChecksum = sha256.convert(bytes).toString();
    if (actualChecksum != expectedChecksum) {
      throw CacheException(message: 'Audio checksum mismatch for alert $alertId');
    }
    try {
      final file = await _fileFor(alertId);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on FileSystemException catch (e) {
      throw CacheException(message: 'Failed to write cached audio for alert $alertId: ${e.message}');
    }
  }

  Future<bool> validateCachedFile({
    required String alertId,
    required String expectedChecksum,
  }) async {
    try {
      final file = await _fileFor(alertId);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return false;
      final actualChecksum = sha256.convert(bytes).toString();
      return actualChecksum == expectedChecksum;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> evict(String alertId) async {
    try {
      final file = await _fileFor(alertId);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (e) {
      throw CacheException(message: 'Failed to evict cached audio for alert $alertId: ${e.message}');
    }
  }

  Future<void> clearAll() async {
    try {
      final dir = await _resolveCacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _cacheDirectory = null;
    } on FileSystemException catch (e) {
      throw CacheException(message: 'Failed to clear alert audio cache: ${e.message}');
    }
  }

  Future<int> getCacheSizeBytes() async {
    final dir = await _resolveCacheDirectory();
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
