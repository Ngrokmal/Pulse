import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/friend_profile_cache_service.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../../domain/entities/agora_engine_event.dart';
import '../../domain/entities/call_participant_entity.dart';
import '../../domain/entities/call_session_entity.dart';
import '../../domain/entities/call_state_entity.dart';
import '../../domain/entities/call_status.dart';
import '../../domain/entities/call_type.dart';
import '../../domain/failures/call_failures.dart';
import '../../domain/repositories/agora_repository.dart';
import '../../domain/usecases/accept_call_usecase.dart';
import '../../domain/usecases/cancel_call_usecase.dart';
import '../../domain/usecases/decline_call_usecase.dart';
import '../../domain/usecases/end_call_usecase.dart';
import '../../domain/usecases/fetch_agora_token_usecase.dart';
import '../../domain/usecases/initiate_call_usecase.dart';
import '../../domain/usecases/join_channel_usecase.dart';
import '../../domain/usecases/leave_channel_usecase.dart';
import '../../domain/usecases/listen_call_status_usecase.dart';
import '../../domain/usecases/mark_call_missed_usecase.dart';
import '../../domain/usecases/refresh_agora_token_usecase.dart';
import '../../domain/usecases/switch_camera_usecase.dart';
import '../../domain/usecases/toggle_camera_usecase.dart';
import '../../domain/usecases/toggle_mute_usecase.dart';
import '../../domain/usecases/toggle_speaker_usecase.dart';
import 'call_state.dart';

/// Caller-side "no answer" timeout (Phase 1 §14/§15) — if the callee hasn't
/// responded within this window, [MarkCallMissedUseCase] fires and the
/// call transitions to [CallPhase.ended].
const Duration kRingingTimeout = Duration(seconds: 45);

/// Drives one call's full lifecycle end to end: outgoing (caller) or
/// incoming (callee) origination, Supabase signaling status transitions,
/// Agora engine join/leave, mute/camera/speaker/switch-camera controls,
/// the connected-call elapsed timer, and teardown.
///
/// One [CallCubit] instance == one call attempt. Created fresh per call
/// (`sl.registerFactory` — see `call_presentation_injection.dart`), not a
/// long-lived singleton like `IncomingCallListenerCubit`.
///
/// Depends directly on [AgoraRepository] (not just the usecases that wrap
/// individual operations) because `initialize`/`engineEvents`/`dispose`
/// have no dedicated usecase in the Foundation Layer — mirroring how
/// `FriendAlertCubit` takes `SupabaseClient` directly for the slice of
/// work no usecase covers.
class CallCubit extends Cubit<CallState> {
  final InitiateCallUseCase initiateCallUseCase;
  final AcceptCallUseCase acceptCallUseCase;
  final DeclineCallUseCase declineCallUseCase;
  final CancelCallUseCase cancelCallUseCase;
  final EndCallUseCase endCallUseCase;
  final MarkCallMissedUseCase markCallMissedUseCase;
  final FetchAgoraTokenUseCase fetchAgoraTokenUseCase;
  final RefreshAgoraTokenUseCase refreshAgoraTokenUseCase;
  final JoinChannelUseCase joinChannelUseCase;
  final LeaveChannelUseCase leaveChannelUseCase;
  final ToggleMuteUseCase toggleMuteUseCase;
  final ToggleCameraUseCase toggleCameraUseCase;
  final SwitchCameraUseCase switchCameraUseCase;
  final ToggleSpeakerUseCase toggleSpeakerUseCase;
  final ListenCallStatusUseCase listenCallStatusUseCase;
  final AgoraRepository agoraRepository;
  final ProfileRepository profileRepository;

  CallCubit({
    required this.initiateCallUseCase,
    required this.acceptCallUseCase,
    required this.declineCallUseCase,
    required this.cancelCallUseCase,
    required this.endCallUseCase,
    required this.markCallMissedUseCase,
    required this.fetchAgoraTokenUseCase,
    required this.refreshAgoraTokenUseCase,
    required this.joinChannelUseCase,
    required this.leaveChannelUseCase,
    required this.toggleMuteUseCase,
    required this.toggleCameraUseCase,
    required this.switchCameraUseCase,
    required this.toggleSpeakerUseCase,
    required this.listenCallStatusUseCase,
    required this.agoraRepository,
    required this.profileRepository,
  }) : super(const CallState.idle());

  String? _currentUserId;

  /// MILESTONE 7 PART B: set as soon as [AgoraRepository.initialize]
  /// succeeds. Relying on join success alone to decide whether
  /// [_teardownEngine] is needed left the engine undisposed whenever
  /// `initialize` succeeded but the subsequent join failed (bad token,
  /// mid-call permission revocation, etc.) — `agoraRepository.dispose()`
  /// was never called for that path.
  bool _engineInitialized = false;

  /// MILESTONE 7 PART B: set synchronously at the start of [endCall],
  /// before any `await`. `state.phase` alone isn't a sufficient re-entry
  /// guard here — it only becomes [CallPhase.ended] *after*
  /// `endCallUseCase`/`_teardownEngine` finish, so a rapid double-tap on
  /// the End button landing inside that window would otherwise pass the
  /// phase check twice (same class of bug the MILESTONE 6 comments on
  /// [accept]/[decline] already describe for their own re-entry guards).
  bool _isEnding = false;

  /// Set when [cancel] is called while [startOutgoingCall]'s
  /// `InitiateCallUseCase` is still in flight (no session id exists yet
  /// to cancel server-side). Checked once that call resolves so the
  /// just-created session is cancelled immediately instead of the tap
  /// being silently lost.
  bool _cancelRequested = false;
  StreamSubscription<CallSessionEntity>? _statusSubscription;
  StreamSubscription<AgoraEngineEvent>? _engineSubscription;
  StreamSubscription? _peerProfileSubscription;
  Timer? _elapsedTimer;
  Timer? _ringingTimeoutTimer;

  // --- Origination ----------------------------------------------------

  /// Caller taps the call button on a friend's profile/chat.
  Future<void> startOutgoingCall({
    required String currentUserId,
    required String calleeId,
    required CallType callType,
  }) async {
    _currentUserId = currentUserId;
    emit(CallState(
      phase: CallPhase.calling,
      callType: callType,
      isSpeakerOn: callType == CallType.video,
      isProcessing: true,
    ));
    _loadPeerProfile(calleeId);

    final result = await initiateCallUseCase.call(
      viewerUid: currentUserId,
      calleeId: calleeId,
      callType: callType,
    );

    result.fold(
      (failure) => emit(state.copyWith(phase: CallPhase.ended, isProcessing: false, failure: failure)),
      (session) {
        if (_cancelRequested) {
          // User tapped Cancel while this request was still in flight —
          // the local UI already moved on (see `cancel()`), so just
          // cancel the now-created session server-side and stop here.
          unawaited(cancelCallUseCase.call(session.id));
          return;
        }
        emit(state.copyWith(session: session, isProcessing: false));
        _watchStatus(session.id);
        _startRingingTimeout(session.id);
      },
    );
  }

  /// Callee's screen is shown for an already-ringing session, delivered by
  /// `IncomingCallListenerCubit`. Does not itself accept/decline — just
  /// wires up state + the status stream so a caller-side cancel while the
  /// callee is still looking at the screen is reflected immediately.
  void presentIncomingCall({
    required String currentUserId,
    required CallSessionEntity incomingSession,
  }) {
    _currentUserId = currentUserId;
    emit(CallState(
      phase: CallPhase.ringingIncoming,
      session: incomingSession,
      callType: incomingSession.callType,
      isSpeakerOn: incomingSession.callType == CallType.video,
    ));
    _loadPeerProfile(incomingSession.callerId);
    _watchStatus(incomingSession.id);
  }

  void _watchStatus(String callId) {
    _statusSubscription?.cancel();
    _statusSubscription = listenCallStatusUseCase.call(callId).listen(
      _onStatusUpdate,
      onError: (_) {},
    );
  }

  void _onStatusUpdate(CallSessionEntity updated) {
    if (isClosed) return;
    emit(state.copyWith(session: updated));

    // MILESTONE 7 PART C: once this call has already reached its terminal
    // phase (via endCall(), a prior status update, or an engine event),
    // skip the status-driven side effects below. Without this, the
    // realtime echo of this same device's own endCallUseCase/cancel/etc.
    // write (or a redundant duplicate Postgres Changes delivery) would
    // re-enter the `declined/cancelled/missed/busy/ended` branches and
    // call `_teardownEngine()` a second time concurrently with the first
    // — a real race, since `_teardownEngine` awaits `leaveChannel()`
    // before `agoraRepository.dispose()` nulls out the engine, leaving a
    // window where two in-flight teardowns could both call into the live
    // Agora engine at once.
    if (state.phase == CallPhase.ended) return;

    switch (updated.status) {
      case CallStatus.accepted:
        if (state.phase == CallPhase.calling || state.phase == CallPhase.ringingIncoming) {
          _cancelRingingTimeout();
          unawaited(_joinCall(updated));
        }
        break;
      case CallStatus.declined:
      case CallStatus.cancelled:
      case CallStatus.missed:
      case CallStatus.busy:
        if (!state.isConnected) {
          _cancelRingingTimeout();
          unawaited(_teardownEngine());
          emit(state.copyWith(phase: CallPhase.ended));
        }
        break;
      case CallStatus.ended:
        _cancelRingingTimeout();
        unawaited(_teardownEngine());
        emit(state.copyWith(phase: CallPhase.ended));
        break;
      case CallStatus.ringing:
        break;
    }
  }

  void _startRingingTimeout(String callId) {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = Timer(kRingingTimeout, () async {
      await markCallMissedUseCase.call(callId);
    });
  }

  void _cancelRingingTimeout() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;
  }

  // --- Callee response --------------------------------------------------

  Future<void> accept() async {
    final session = state.session;
    // MILESTONE 6: `isProcessing` guard added — the phase check alone
    // isn't enough, since phase only leaves `ringingIncoming` after
    // `acceptCallUseCase` resolves, so a double-tap landing before that
    // first await yields would previously pass the phase check twice and
    // fire two concurrent accept requests.
    if (session == null || state.phase != CallPhase.ringingIncoming || state.isProcessing) return;
    emit(state.copyWith(isProcessing: true, clearFailure: true));

    final result = await acceptCallUseCase.call(session.id);
    result.fold(
      (failure) => emit(state.copyWith(isProcessing: false, failure: failure)),
      (_) {
        final accepted = session.copyWith(status: CallStatus.accepted, acceptedAt: DateTime.now());
        emit(state.copyWith(session: accepted, isProcessing: false));
        unawaited(_joinCall(accepted));
      },
    );
  }

  Future<void> decline() async {
    final session = state.session;
    // MILESTONE 6: added phase + isProcessing guards, matching accept()'s
    // — previously decline() had neither, so it could fire twice (e.g.
    // double-tap, or a stray call after accept() had already moved the
    // phase on) and call declineCallUseCase redundantly.
    if (session == null || state.phase != CallPhase.ringingIncoming || state.isProcessing) return;
    emit(state.copyWith(isProcessing: true, clearFailure: true));
    await declineCallUseCase.call(session.id);
    emit(state.copyWith(
      phase: CallPhase.ended,
      isProcessing: false,
      session: session.copyWith(status: CallStatus.declined),
    ));
  }

  // --- Caller cancel ------------------------------------------------------

  Future<void> cancel() async {
    final session = state.session;
    // MILESTONE 6: guards against a double-tap (or a stray call after the
    // call already ended via a realtime update) firing cancelCallUseCase
    // — or setting _cancelRequested — a second time.
    if (state.phase == CallPhase.ended || state.isProcessing) return;
    if (session == null) {
      // Still waiting on InitiateCallUseCase — nothing exists server-side
      // to cancel yet. Record the request (handled in startOutgoingCall's
      // continuation above) and end the local UI now rather than leaving
      // the Cancel button a no-op.
      _cancelRequested = true;
      emit(state.copyWith(phase: CallPhase.ended, isProcessing: false));
      return;
    }
    _cancelRingingTimeout();
    emit(state.copyWith(isProcessing: true, clearFailure: true));
    await cancelCallUseCase.call(session.id);
    emit(state.copyWith(
      phase: CallPhase.ended,
      isProcessing: false,
      session: session.copyWith(status: CallStatus.cancelled),
    ));
  }

  // --- Agora join / connected lifecycle -----------------------------------

  Future<void> _joinCall(CallSessionEntity session) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || isClosed) return;

    emit(state.copyWith(phase: CallPhase.connecting));

    final uid = session.agoraUidFor(currentUserId);
    if (uid == null) {
      emit(state.copyWith(
        phase: CallPhase.ended,
        failure: const CallPermissionFailure(),
      ));
      return;
    }

    final videoEnabled = session.callType == CallType.video;
    final hasDevicePermissions = await _ensureCallPermissions(videoEnabled: videoEnabled);
    if (!hasDevicePermissions) {
      if (!isClosed) {
        emit(state.copyWith(
          phase: CallPhase.ended,
          failure: const CallDevicePermissionFailure(),
        ));
      }
      return;
    }

    final tokenResult = await fetchAgoraTokenUseCase.call(
      callId: session.id,
      channelName: session.channelName,
      uid: uid,
    );

    final credentials = tokenResult.fold((failure) {
      emit(state.copyWith(phase: CallPhase.ended, failure: failure));
      return null;
    }, (creds) => creds);
    if (credentials == null || isClosed) return;

    final initResult = await agoraRepository.initialize(credentials.appId);
    final initFailure = initResult.fold((f) => f, (_) => null);
    if (initFailure != null) {
      emit(state.copyWith(phase: CallPhase.ended, failure: initFailure));
      return;
    }
    _engineInitialized = true;

    _engineSubscription ??= agoraRepository.engineEvents.listen(_onEngineEvent);

    final joinResult = await joinChannelUseCase.call(credentials: credentials, videoEnabled: videoEnabled);
    joinResult.fold(
      (failure) {
        emit(state.copyWith(phase: CallPhase.ended, failure: failure));
        // MILESTONE 7 PART B: the engine was initialized above even
        // though the join itself failed — without this, `_engineInitialized`
        // would stay false and `close()` would never dispose it.
        unawaited(_teardownEngine());
      },
      (_) {
        emit(state.copyWith(
          localParticipant: CallParticipantEntity(
            userId: currentUserId,
            displayName: '',
            agoraUid: uid,
            isMuted: false,
            isCameraOn: videoEnabled,
          ),
        ));
      },
    );
  }

  void _onEngineEvent(AgoraEngineEvent event) {
    if (isClosed) return;
    if (event is AgoraUserJoined) {
      emit(state.copyWith(
        phase: CallPhase.connected,
        remoteParticipant: CallParticipantEntity(
          userId: state.session?.otherParticipantId(_currentUserId ?? '') ?? '',
          displayName: state.peerDisplayName ?? '',
          avatarUrl: state.peerAvatarUrl,
          agoraUid: event.remoteUid,
        ),
      ));
      _startElapsedTimer();
    } else if (event is AgoraUserLeft) {
      _stopElapsedTimer();
      emit(state.copyWith(phase: CallPhase.ended));
      unawaited(_teardownEngine());
    } else if (event is AgoraConnectionLost) {
      if (state.phase == CallPhase.connected) {
        emit(state.copyWith(phase: CallPhase.reconnecting));
      }
    } else if (event is AgoraConnectionRestored) {
      if (state.phase == CallPhase.reconnecting) {
        emit(state.copyWith(phase: CallPhase.connected));
      }
    } else if (event is AgoraTokenExpiringSoon) {
      final session = state.session;
      final uid = state.localParticipant?.agoraUid;
      if (session != null && uid != null) {
        unawaited(_renewAgoraToken(callId: session.id, channelName: session.channelName, uid: uid));
      }
    } else if (event is AgoraEngineError) {
      emit(state.copyWith(failure: AgoraEngineFailure(event.message)));
    }
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      if (state.phase != CallPhase.connected) return;
      emit(state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1)));
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  /// Fetches a new Agora credential (mirroring the join-time flow) and, on
  /// success, pushes just the token into the *live* engine via
  /// [AgoraRepository.renewToken] — the piece the Foundation Layer's
  /// `AgoraTokenExpiringSoon` handling was missing. Transparent to the
  /// user: no re-join, no UI state change on success.
  Future<void> _renewAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  }) async {
    final result = await refreshAgoraTokenUseCase.call(callId: callId, channelName: channelName, uid: uid);
    if (isClosed) return;
    await result.fold(
      (failure) async {
        // Non-fatal: the current token is still valid for a short grace
        // window after onTokenPrivilegeWillExpire fires. Surface it so it
        // shows up in logs/telemetry without ending an otherwise-healthy
        // call.
        emit(state.copyWith(failure: failure));
      },
      (credentials) => agoraRepository.renewToken(credentials.token),
    );
  }

  /// Requests microphone permission unconditionally, and camera permission
  /// only for a video call, before the engine is initialized/joined.
  /// Returns false (without throwing) if either required permission ends
  /// up denied — the caller surfaces [CallDevicePermissionFailure].
  Future<bool> _ensureCallPermissions({required bool videoEnabled}) async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return false;
    if (videoEnabled) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) return false;
    }
    return true;
  }

  /// Type-erased live-engine handle for video-preview widgets only (see
  /// [AgoraRepository.engineHandle]) — `null` until the engine has joined.
  Object? get rtcEngineHandle => agoraRepository.engineHandle;

  // --- In-call controls -----------------------------------------------

  Future<void> toggleMute() async {
    final next = !state.isMuted;
    final local = state.localParticipant;
    if (local != null) emit(state.copyWith(localParticipant: local.copyWith(isMuted: next)));
    final result = await toggleMuteUseCase.call(next);
    result.fold((failure) => emit(state.copyWith(failure: failure)), (_) {});
  }

  Future<void> toggleCamera() async {
    if (!state.isVideoCall) return;
    final next = !state.isCameraOn;
    final local = state.localParticipant;
    if (local != null) emit(state.copyWith(localParticipant: local.copyWith(isCameraOn: next)));
    final result = await toggleCameraUseCase.call(next);
    result.fold((failure) => emit(state.copyWith(failure: failure)), (_) {});
  }

  Future<void> switchCamera() async {
    if (!state.isVideoCall) return;
    final result = await switchCameraUseCase.call();
    result.fold(
      (failure) => emit(state.copyWith(failure: failure)),
      (_) => emit(state.copyWith(isFrontCamera: !state.isFrontCamera)),
    );
  }

  Future<void> toggleSpeaker() async {
    final next = !state.isSpeakerOn;
    emit(state.copyWith(isSpeakerOn: next));
    final result = await toggleSpeakerUseCase.call(next);
    result.fold((failure) => emit(state.copyWith(failure: failure)), (_) {});
  }

  // --- End -----------------------------------------------------------

  Future<void> endCall({String endReason = 'ended'}) async {
    // MILESTONE 7 PART B: guards a rapid double-tap on the End button
    // (which, unlike Accept/Decline/Cancel, had no re-entry guard at
    // all) from firing `endCallUseCase`/`_teardownEngine` twice for the
    // same call. See `_isEnding`'s doc comment for why `state.phase`
    // alone isn't enough here.
    if (state.phase == CallPhase.ended || _isEnding) return;
    _isEnding = true;
    final session = state.session;
    _stopElapsedTimer();
    _cancelRingingTimeout();
    if (session != null) {
      await endCallUseCase.call(callId: session.id, endReason: endReason);
    }
    await _teardownEngine();
    if (!isClosed) {
      emit(state.copyWith(
        phase: CallPhase.ended,
        session: session?.copyWith(status: CallStatus.ended, endReason: endReason),
      ));
    }
  }

  /// MILESTONE 7 PART C: shares a single in-flight teardown across
  /// concurrent callers instead of letting each start its own. Two call
  /// sites can legitimately race here — e.g. `endCall()` (user taps End)
  /// and the `AgoraUserLeft` engine event (remote peer leaves the
  /// channel) can both fire within the same tick while `state.phase` is
  /// still `connected` — and without this, both would call
  /// `leaveChannelUseCase.call()`/`agoraRepository.dispose()`
  /// concurrently instead of one waiting on the other.
  Future<void>? _teardownFuture;

  Future<void> _teardownEngine() {
    return _teardownFuture ??= _doTeardownEngine().whenComplete(() => _teardownFuture = null);
  }

  Future<void> _doTeardownEngine() async {
    _engineInitialized = false;
    try {
      await leaveChannelUseCase.call();
    } catch (_) {}
    try {
      await agoraRepository.dispose();
    } catch (_) {}
  }

  // --- Peer profile lookup ---------------------------------------------

  void _loadPeerProfile(String peerId) {
    final cached = FriendProfileCacheService.instance.getCachedSync(peerId);
    if (cached != null) {
      emit(state.copyWith(peerDisplayName: cached.displayName, peerAvatarUrl: cached.avatarUrl));
    }
    _peerProfileSubscription?.cancel();
    _peerProfileSubscription = profileRepository.streamProfile(peerId).listen(
      (profile) {
        if (isClosed) return;
        emit(state.copyWith(peerDisplayName: profile.displayName, peerAvatarUrl: profile.avatarUrl));
        unawaited(FriendProfileCacheService.instance.saveIfChanged(profile));
      },
      onError: (_) {},
    );
  }

  @override
  Future<void> close() async {
    _statusSubscription?.cancel();
    _engineSubscription?.cancel();
    _peerProfileSubscription?.cancel();
    _elapsedTimer?.cancel();
    _ringingTimeoutTimer?.cancel();
    if (_engineInitialized) {
      await _teardownEngine();
    }
    return super.close();
  }
}
