import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'media_cache_manager.dart';

class CacheInspector {
  CacheInspector._privateConstructor();
  static final CacheInspector instance = CacheInspector._privateConstructor();

  static const String _voicePrefix = 'voice_';

  bool _isVoiceFile(FileSystemEntity entity) {
    final name = entity.path.split(Platform.pathSeparator).last;
    return name.startsWith(_voicePrefix);
  }

  Future<List<File>> _tempFiles() async {
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) return const [];
    final entities = await dir.list(recursive: false, followLinks: false).toList();
    return entities.whereType<File>().toList();
  }

  Future<int> mediaCacheSizeBytes() async {
    final files = await _tempFiles();
    int total = 0;
    for (final file in files) {
      if (_isVoiceFile(file)) continue;
      try {
        total += await file.length();
      } catch (_) {}
    }
    return total;
  }

  Future<int> voiceCacheSizeBytes() async {
    final files = await _tempFiles();
    int total = 0;
    for (final file in files) {
      if (!_isVoiceFile(file)) continue;
      try {
        total += await file.length();
      } catch (_) {}
    }
    return total;
  }

  Future<void> clearMediaCache() async {
    final files = await _tempFiles();
    for (final file in files) {
      if (_isVoiceFile(file)) continue;
      try {
        await file.delete();
      } catch (_) {}
    }
    MediaCacheManager.instance.forceFlushImageMemory();
  }

  Future<void> clearVoiceCache() async {
    final files = await _tempFiles();
    for (final file in files) {
      if (!_isVoiceFile(file)) continue;
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
