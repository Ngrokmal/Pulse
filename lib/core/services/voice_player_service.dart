import 'dart:async';
import 'package:just_audio/just_audio.dart';

class VoicePlayerService {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _completionSub;

  VoicePlayerService() {
    _completionSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.pause().catchError((_) {});
        _player.seek(Duration.zero).catchError((_) {});
      }
    });
  }

  Future<void> setUrl(String url) => _player.setUrl(url);
  Future<void> setFilePath(String path) => _player.setFilePath(path);
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<bool> get isPlayingStream => _player.playerStateStream.map(
        (state) => state.playing && state.processingState != ProcessingState.completed,
      );

  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  bool get isPlaying => _player.playing && _player.processingState != ProcessingState.completed;

  Future<void> dispose() async {
    await _completionSub?.cancel();
    await _player.dispose();
  }
}
