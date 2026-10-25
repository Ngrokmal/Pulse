import 'dart:io';
import '../entities/voice_message_entity.dart';

abstract class VoiceRecordingService {
  Future<void> startRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  Future<VoiceMessageEntity> stopRecording();
  Future<void> cancelRecording();
  Stream<double> get amplitudeStream;
  bool get isRecording;
  bool get isPaused;

  int get elapsedMs;

  List<double> get liveWaveform;

  String? get currentFilePath;
}

abstract class VoiceUploadService {
  Future<String> uploadVoice({required File file, required String folder});
}

abstract class VoiceCompressionService {
  Future<File> compress(File source);
}

abstract class VoicePlaybackController {
  Future<void> play(String url);
  Future<void> pausePlayback();
  Future<void> resumePlayback();
  Future<void> stopPlayback();
  Future<void> seekTo(Duration position);
  void setSpeed(double speed);
  double get currentSpeed;
  Duration get position;
  Duration get duration;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<bool> get isPlayingStream;
  Future<void> dispose();
}

abstract class VoicePlaybackSpeedController {
  void setSpeed(double speed);
  double get currentSpeed;
}

abstract class VoiceSeekController {
  void seekTo(Duration position);
  Duration get position;
  Duration get duration;
}

abstract class VoiceReplyContext {
  String? get replyToMessageId;
}

abstract class VoiceReactionService {
  Future<void> addReaction({required String messageId, required String reaction});
  Future<void> removeReaction({required String messageId, required String reaction});
}
