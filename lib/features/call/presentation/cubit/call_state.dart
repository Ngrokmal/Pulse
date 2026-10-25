import '../../../../core/errors/failures.dart';
import '../../domain/entities/call_participant_entity.dart';
import '../../domain/entities/call_session_entity.dart';
import '../../domain/entities/call_state_entity.dart';
import '../../domain/entities/call_type.dart';
import '../../domain/failures/call_failures.dart';

/// Presentation-level call state consumed by [CallCubit]'s four screens
/// (Incoming/Outgoing/ActiveCall/CallEnded).
///
/// Wraps the domain [CallPhase]/[CallSessionEntity]/[CallParticipantEntity]
/// shapes already defined in `domain/entities/call_state_entity.dart` (that
/// file explicitly reserves those types for "the future CallCubit"), and
/// adds the handful of fields that only make sense at the UI layer:
/// speaker/front-camera toggle state (not modeled by the Agora engine
/// contract), an in-flight [isProcessing] flag for button spinners, a
/// [Failure] (not a bare string) matching `AuthFailureState`'s
/// `Failure failure` convention, and the peer's display name/avatar
/// (resolved via `ProfileRepository`/`FriendProfileCacheService`, never
/// carried by the signaling-only [CallSessionEntity]).
///
/// Hand-rolled, no freezed/equatable — matching `FriendAlertState`/
/// `AuthState`'s plain-class approach (Open Decision #4).
class CallState {
  final CallPhase phase;
  final CallSessionEntity? session;
  final CallType callType;
  final CallParticipantEntity? localParticipant;
  final CallParticipantEntity? remoteParticipant;
  final Duration elapsed;
  final bool isSpeakerOn;
  final bool isFrontCamera;
  final bool isProcessing;
  final Failure? failure;
  final String? peerDisplayName;
  final String? peerAvatarUrl;

  const CallState({
    required this.phase,
    this.session,
    this.callType = CallType.audio,
    this.localParticipant,
    this.remoteParticipant,
    this.elapsed = Duration.zero,
    this.isSpeakerOn = false,
    this.isFrontCamera = true,
    this.isProcessing = false,
    this.failure,
    this.peerDisplayName,
    this.peerAvatarUrl,
  });

  const CallState.idle()
      : phase = CallPhase.idle,
        session = null,
        callType = CallType.audio,
        localParticipant = null,
        remoteParticipant = null,
        elapsed = Duration.zero,
        isSpeakerOn = false,
        isFrontCamera = true,
        isProcessing = false,
        failure = null,
        peerDisplayName = null,
        peerAvatarUrl = null;

  bool get isVideoCall => callType == CallType.video;
  bool get isMuted => localParticipant?.isMuted ?? false;
  bool get isCameraOn => localParticipant?.isCameraOn ?? true;
  bool get isConnected => phase == CallPhase.connected || phase == CallPhase.reconnecting;

  /// MILESTONE 7 PART B: clean, user-facing text for [failure] — never
  /// `failure.message` directly. Some `Failure` subclasses in this module
  /// (`AgoraEngineFailure`, `AgoraTokenFailure`, `UnknownCallFailure`) are
  /// sometimes constructed from a raw `Exception.toString()`/SDK error in
  /// the data layer (see `call_repository_impl.dart`/
  /// `agora_repository_impl.dart`), so their `.message` can't be trusted
  /// for display. Only failure types whose `.message` is always a
  /// curated, human-authored string (see `call_failures.dart`) are
  /// surfaced as-is; everything else falls back to a single generic,
  /// localization-ready message.
  String? get errorMessage {
    final f = failure;
    if (f == null) return null;
    final hasCuratedMessage = f is CallNotFoundFailure ||
        f is CallPermissionFailure ||
        f is CallNotFriendFailure ||
        f is CalleeBusyFailure ||
        f is CallAlreadyActiveFailure ||
        f is CallRaceLostFailure ||
        f is CallDevicePermissionFailure ||
        f is CallValidationFailure;
    return hasCuratedMessage ? f.message : 'Something went wrong with the call. Please try again.';
  }

  CallState copyWith({
    CallPhase? phase,
    CallSessionEntity? session,
    CallType? callType,
    CallParticipantEntity? localParticipant,
    CallParticipantEntity? remoteParticipant,
    Duration? elapsed,
    bool? isSpeakerOn,
    bool? isFrontCamera,
    bool? isProcessing,
    Failure? failure,
    bool clearFailure = false,
    String? peerDisplayName,
    String? peerAvatarUrl,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      session: session ?? this.session,
      callType: callType ?? this.callType,
      localParticipant: localParticipant ?? this.localParticipant,
      remoteParticipant: remoteParticipant ?? this.remoteParticipant,
      elapsed: elapsed ?? this.elapsed,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      isProcessing: isProcessing ?? this.isProcessing,
      failure: clearFailure ? null : (failure ?? this.failure),
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
    );
  }
}
