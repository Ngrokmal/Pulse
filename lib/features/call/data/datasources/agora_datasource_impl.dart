import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../../domain/entities/agora_engine_event.dart';
import 'agora_datasource.dart';

/// Concrete [AgoraDataSource]. Per Phase 1 §6, this is the ONLY file in the
/// entire project permitted to import `agora_rtc_engine` — every Agora SDK
/// type is translated into a domain-level [AgoraEngineEvent] before leaving
/// this class, so nothing above the datasource boundary (repository,
/// usecases, and eventually the Cubit) ever touches the SDK directly.
///
/// One [RtcEngine] instance is created lazily on [initializeEngine] and
/// fully torn down in [destroyEngine] — not kept warm across calls, per
/// Phase 1 §6's leak-avoidance rationale.
///
/// MILESTONE 5: [renewToken] closes the gap the Foundation Layer flagged —
/// [AgoraTokenExpiringSoon] now has a corresponding action the Cubit can
/// take (see `CallCubit._onEngineEvent`) instead of only being observable.
/// [engineHandle] exposes the live engine (type-erased as `Object?`) so
/// presentation-layer video-preview widgets can construct an
/// `AgoraVideoView` — the only other addition this milestone makes to the
/// datasource surface.
class AgoraDataSourceImpl implements AgoraDataSource {
  RtcEngine? _engine;
  final StreamController<AgoraEngineEvent> _eventController = StreamController<AgoraEngineEvent>.broadcast();

  @override
  Stream<AgoraEngineEvent> get events => _eventController.stream;

  @override
  Future<void> initializeEngine(String appId) async {
    if (_engine != null) return;

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          _eventController.add(AgoraUserJoined(remoteUid));
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          _eventController.add(AgoraUserLeft(remoteUid));
        },
        onConnectionStateChanged: (
          RtcConnection connection,
          ConnectionStateType state,
          ConnectionChangedReasonType reason,
        ) {
          // Phase 1 §17/§18: connection loss/restoration drives a bounded
          // "Reconnecting" window at the Cubit layer — it must NOT by
          // itself end an already-connected call. This datasource only
          // reports the raw signal; that policy lives above this layer.
          if (state == ConnectionStateType.connectionStateReconnecting ||
              state == ConnectionStateType.connectionStateFailed) {
            _eventController.add(const AgoraConnectionLost());
          } else if (state == ConnectionStateType.connectionStateConnected) {
            _eventController.add(const AgoraConnectionRestored());
          }
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          _eventController.add(const AgoraTokenExpiringSoon());
        },
        onError: (ErrorCodeType err, String msg) {
          _eventController.add(AgoraEngineError('$err: $msg'));
        },
      ),
    );

    _engine = engine;
  }

  @override
  Future<void> joinChannel({
    required String token,
    required String channelName,
    required int uid,
    required bool videoEnabled,
  }) async {
    final engine = _requireEngine();

    await engine.enableAudio();
    if (videoEnabled) {
      await engine.enableVideo();
    } else {
      await engine.disableVideo();
    }

    await engine.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishCameraTrack: videoEnabled,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
  }

  @override
  Future<void> leaveChannel() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.leaveChannel();
  }

  @override
  Future<void> muteLocalAudio(bool muted) async {
    await _requireEngine().muteLocalAudioStream(muted);
  }

  @override
  Future<void> enableLocalVideo(bool enabled) async {
    await _requireEngine().enableLocalVideo(enabled);
  }

  @override
  Future<void> switchCamera() async {
    await _requireEngine().switchCamera();
  }

  @override
  Future<void> setEnableSpeakerphone(bool enabled) async {
    await _requireEngine().setEnableSpeakerphone(enabled);
  }

  @override
  Future<void> renewToken(String token) async {
    await _requireEngine().renewToken(token);
  }

  @override
  Object? get engineHandle => _engine;

  @override
  Future<void> destroyEngine() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } finally {
      await engine.release();
    }
  }

  RtcEngine _requireEngine() {
    final engine = _engine;
    if (engine == null) {
      throw StateError('AgoraDataSourceImpl.initializeEngine() must be called before use.');
    }
    return engine;
  }
}
