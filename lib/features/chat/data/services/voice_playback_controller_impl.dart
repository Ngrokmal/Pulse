import 'dart:async';
import '../../../../core/services/voice_local_cache_service.dart';
import '../../../../core/services/voice_player_service.dart';
import '../../domain/services/voice_recording_service.dart';

const Duration _kLoadTimeout = Duration(seconds: 15);

class VoicePlaybackControllerImpl implements VoicePlaybackController {
  final VoicePlayerService _player;
  final VoiceLocalCacheService _cache;
  VoicePlaybackControllerImpl(this._player, {VoiceLocalCacheService? cache})
      : _cache = cache ?? VoiceLocalCacheService.instance;

  String? _loadedUrl;
  double _speed = 1.0;

  @override
  Future<void> play(String url) async {
    if (_loadedUrl != url) {
      try {
        // Bug 4/5 fix: never stream straight from the network — resolve to
        // a local file first (cache hit = instant + works offline; cache
        // miss = download once, then cached for every future play,
        // including this same session's replay).
        final file = await _cache.getOrDownload(url).timeout(_kLoadTimeout);
        await _player.setFilePath(file.path).timeout(_kLoadTimeout);
      } catch (e) {
        _loadedUrl = null;
        rethrow;
      }
      _loadedUrl = url;
      try {
        await _player.setSpeed(_speed);
      } catch (_) {
        // non-fatal — playback can still proceed at default speed
      }
    }
    await _player.play();
  }

  @override
  Future<void> pausePlayback() => _player.pause();

  @override
  Future<void> resumePlayback() => _player.play();

  @override
  Future<void> stopPlayback() => _player.stop();

  @override
  Future<void> seekTo(Duration position) => _player.seek(position);

  @override
  void setSpeed(double speed) {
    _speed = speed;
    _player.setSpeed(speed);
  }

  @override
  double get currentSpeed => _speed;

  @override
  Duration get position => _player.position;

  @override
  Duration get duration => _player.duration;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get isPlayingStream => _player.isPlayingStream;

  @override
  Future<void> dispose() => _player.dispose();
}
