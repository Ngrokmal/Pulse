import '../../domain/entities/agora_engine_event.dart';

/// Contract for the Agora RTC engine surface (Phase 1 §6). Deliberately
/// contains no `agora_rtc_engine` import — the concrete
/// [AgoraDataSourceImpl] (Milestone 5) is the only file in the project
/// permitted to import that package; every Agora SDK type is translated
/// into a domain-level [AgoraEngineEvent] (or, for the two narrow
/// exceptions below, an untyped `Object?`) before leaving that class.
abstract class AgoraDataSource {
  Future<void> initializeEngine(String appId);

  Future<void> joinChannel({
    required String token,
    required String channelName,
    required int uid,
    required bool videoEnabled,
  });

  Future<void> leaveChannel();

  Future<void> muteLocalAudio(bool muted);

  Future<void> enableLocalVideo(bool enabled);

  Future<void> switchCamera();

  Future<void> setEnableSpeakerphone(bool enabled);

  /// Domain-level event stream — the concrete implementation translates raw
  /// Agora SDK callbacks (onUserJoined, onUserOffline,
  /// onConnectionStateChanged, onTokenPrivilegeWillExpire, onError) into
  /// these, so no Agora type ever crosses this boundary.
  Stream<AgoraEngineEvent> get events;

  /// MILESTONE 5 addition: pushes a freshly-fetched token into the *live*
  /// engine in response to [AgoraTokenExpiringSoon] — closes the gap the
  /// Foundation Layer flagged (that milestone could only emit the event,
  /// not act on it). Maps to Agora's own `RtcEngine.renewToken`.
  Future<void> renewToken(String token);

  /// MILESTONE 5 addition: a type-erased handle to the live engine
  /// instance, used ONLY by presentation-layer video-preview widgets to
  /// construct an `AgoraVideoView`'s `VideoViewController`. Typed as
  /// `Object?` (not `RtcEngine?`) so this interface still never imports
  /// `agora_rtc_engine` — the concrete SDK type is recovered with a cast
  /// only inside the small set of widgets that need it, mirroring how the
  /// datasource impl remains the sole owner of the real engine lifecycle.
  Object? get engineHandle;

  Future<void> destroyEngine();
}
