import 'dart:async';
import 'package:just_audio/just_audio.dart';

class VoicePlayerService {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _completionSub;

  VoicePlayerService() {
    // BUG FIX (playback UI never resets): just_audio does NOT automatically
    // flip `playing` back to false when a track finishes naturally — it
    // stays true forever with processingState == completed unless the app
    // explicitly reacts to it. Without this, isPlayingStream never emits
    // false on natural completion, so the bubble's pause icon / waveform /
    // timer stay stuck in the "still playing" state indefinitely. Pausing +
    // seeking to zero here both resets playback position for the next tap
    // AND makes `playing` flip to false, which isPlayingStream below then
    // correctly reports.
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

  // BUG FIX (playback UI never resets), belt-and-suspenders: even if a
  // caller reads `playing` directly off a raw PlayerState instead of going
  // through the completion-handling above, treat a `completed` processing
  // state as "not playing" so nothing downstream can observe a stale
  // "still playing" signal.
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
