import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/call_history_page_entity.dart';
import '../entities/call_response.dart';
import '../entities/call_session_entity.dart';
import '../entities/call_type.dart';
import '../entities/agora_credentials_entity.dart';

/// Contract for the call module's signaling/data operations (Phase 1 §4.2).
/// Implemented by `CallRepositoryImpl` (data layer — NOT part of this
/// milestone; that implementation is the one that will actually talk to
/// Supabase, and is deferred until the Data Layer milestone).
///
/// Follows the exact `Future<Either<Failure, T>>` shape already used by
/// `FriendRepository` (features/profile/domain/repositories/friend_repository.dart)
/// per Open Decision #3, since `InitiateCallUseCase` reads directly from
/// that repository and this keeps both call sites consistent.
abstract class CallRepository {
  /// Creates a new `call_sessions` row (status starts at 'ringing') and
  /// triggers the invite push via the existing push service (Phase 1 §8/§11).
  /// Friend-check and already-in-a-call validation happen in
  /// `InitiateCallUseCase`, above this repository — this method's job is
  /// purely to persist + notify.
  Future<Either<Failure, CallSessionEntity>> createCall({
    required String calleeId,
    required CallType callType,
  });

  /// Callee's response to a ringing call: accept, decline, or busy
  /// (Phase 1 §7/§12/§13).
  Future<Either<Failure, void>> respondToCall({
    required String callId,
    required CallResponse response,
  });

  /// Caller cancels a call still in 'ringing' (Phase 1 §7).
  Future<Either<Failure, void>> cancelCall(String callId);

  /// Either participant ends a 'connected' call (Phase 1 §7).
  Future<Either<Failure, void>> endCall({
    required String callId,
    required String endReason,
  });

  /// Marks a call 'missed' after the caller-side ringing timeout fires
  /// (Phase 1 §14/§15), or via the defensive stale-row reconciliation.
  Future<Either<Failure, void>> markMissed(String callId);

  /// Live stream of `call_sessions` rows where the current user is the
  /// callee and status = 'ringing' — powers `IncomingCallListenerCubit`
  /// (Phase 1 §10/§20). Presentation-layer consumer is out of scope here;
  /// only the contract is defined.
  Stream<CallSessionEntity> watchIncomingCalls(String userId);

  /// Live stream of status changes for one call, used by both caller and
  /// callee (Phase 1 §11/§20).
  Stream<CallSessionEntity> watchCallStatus(String callId);

  /// Cursor-paginated call history (Phase 1 §16, Open Decision #8 —
  /// in-scope for this build).
  Future<Either<Failure, CallHistoryPageEntity>> getCallHistory({
    required String userId,
    String? cursor,
    int limit = 20,
  });

  /// Fetches a fresh Agora token via the (not-yet-created)
  /// `generate-agora-token` Edge Function (Phase 1 §9).
  Future<Either<Failure, AgoraCredentialsEntity>> getAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  });

  /// Proactive refresh, invoked on Agora's `onTokenPrivilegeWillExpire`
  /// (Phase 1 §9) — same shape as [getAgoraToken], kept as a separate
  /// method so call sites/telemetry can distinguish "initial fetch" from
  /// "mid-call refresh".
  Future<Either<Failure, AgoraCredentialsEntity>> refreshAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  });
}
