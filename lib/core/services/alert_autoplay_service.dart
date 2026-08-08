import 'dart:async';
import 'package:just_audio/just_audio.dart';

class AlertAutoplayService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playAndAwaitCompletion(
    String filePath, {
    Duration safetyTimeout = const Duration(seconds: 20),
  }) async {
    try {
      await _player.stop();
    } catch (_) {}

    final completer = Completer<void>();
    StreamSubscription<PlayerState>? sub;

    sub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!completer.isCompleted) completer.complete();
      }
    }, onError: (_) {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await _player.setFilePath(filePath);
      await _player.play();
      await completer.future.timeout(
        safetyTimeout,
        onTimeout: () {},
      );
    } finally {
      await sub.cancel();
      try {
        await _player.stop();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
