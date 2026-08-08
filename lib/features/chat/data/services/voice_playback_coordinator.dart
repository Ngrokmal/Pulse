import '../../domain/services/voice_recording_service.dart';

class VoicePlaybackCoordinator {
  VoicePlaybackCoordinator._privateConstructor();
  static final VoicePlaybackCoordinator instance = VoicePlaybackCoordinator._privateConstructor();

  VoicePlaybackController? _activeController;

  Future<void> setActive(VoicePlaybackController controller) async {
    final previous = _activeController;
    _activeController = controller;
    if (previous != null && !identical(previous, controller)) {
      try {
        await previous.pausePlayback();
      } catch (_) {
      }
    }
  }

  void clearIfActive(VoicePlaybackController controller) {
    if (identical(_activeController, controller)) {
      _activeController = null;
    }
  }
}
