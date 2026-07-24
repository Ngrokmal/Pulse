import '../../domain/services/voice_recording_service.dart';

/// Bug 3 fix: each [VoiceMessageBubble] creates its own independent
/// [VoicePlaybackController]/player (via `registerFactory` in DI), so
/// nothing previously stopped two bubbles from playing at once. This
/// singleton is the single source of truth for "which controller is
/// currently the active one" — WhatsApp behavior: starting playback on B
/// immediately pauses whatever A was playing.
///
/// Deliberately NOT registered in DI / not a bloc: this is transient
/// playback UI coordination, not app state, and every bubble already has a
/// reference to its own controller — the coordinator just needs to be
/// reachable from all of them via a single shared instance.
class VoicePlaybackCoordinator {
  VoicePlaybackCoordinator._privateConstructor();
  static final VoicePlaybackCoordinator instance = VoicePlaybackCoordinator._privateConstructor();

  VoicePlaybackController? _activeController;

  /// Call right before starting/resuming playback on [controller]. Pauses
  /// whatever else was playing first. Safe to call even if [controller] is
  /// already the active one (no-op in that case).
  Future<void> setActive(VoicePlaybackController controller) async {
    final previous = _activeController;
    _activeController = controller;
    if (previous != null && !identical(previous, controller)) {
      try {
        await previous.pausePlayback();
      } catch (_) {
        // Previous controller's underlying player may already be
        // disposed/gone (its bubble scrolled off and unmounted) — nothing
        // further to do, it can no longer be "playing" either way.
      }
    }
  }

  /// Call when a controller is disposed or explicitly stopped, so the
  /// coordinator doesn't keep a dangling reference to it as "active".
  void clearIfActive(VoicePlaybackController controller) {
    if (identical(_activeController, controller)) {
      _activeController = null;
    }
  }
}
