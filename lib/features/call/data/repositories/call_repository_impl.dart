import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/services/push_notification_sender_service.dart';
import '../../domain/entities/agora_credentials_entity.dart';
import '../../domain/entities/call_history_page_entity.dart';
import '../../domain/entities/call_response.dart';
import '../../domain/entities/call_session_entity.dart';
import '../../domain/entities/call_type.dart';
import '../../domain/failures/call_failures.dart';
import '../../domain/repositories/call_repository.dart';
import '../datasources/call_realtime_datasource.dart';
import '../datasources/call_remote_datasource.dart';
import '../models/call_session_model.dart';

/// Concrete [CallRepository]. Orchestrates [CallRemoteDataSource] (CRUD),
/// [CallRealtimeDataSource] (subscriptions), and reuses the existing,
/// unmodified [PushNotificationSenderService] for the invite push — exactly
/// the "existing modules to reuse" list from the frozen Phase 1 architecture
/// (§4). No Firebase/Chat/Friend/Notification module code was changed to
/// support this; only its already-public `sendChatMessageNotification` API
/// is called, with a `data` payload shaped for the (not-yet-built) FCM
/// routing branch described in Phase 1 §17.
///
/// Error handling follows this project's established convention (see
/// `FriendRepositoryImpl`/`ChatRepositoryImpl`): datasource exceptions are
/// caught here and mapped to `Failure` subtypes — the datasource layer
/// itself does not know about `Either`/`Failure` at all.
///
/// SCHEMA DEPENDENCY: see the header comment on `CallRemoteDataSourceImpl`
/// — every method below will fail at runtime until the `call_sessions`/
/// `call_events` schema and `generate-agora-token` function exist. That
/// backend work is explicitly out of scope for this milestone.
class CallRepositoryImpl implements CallRepository {
  final CallRemoteDataSource remoteDataSource;
  final CallRealtimeDataSource realtimeDataSource;
  final SupabaseClient supabase;
  final PushNotificationSenderService pushNotificationSender;
  final Uuid _uuid = const Uuid();

  CallRepositoryImpl({
    required this.remoteDataSource,
    required this.realtimeDataSource,
    required this.supabase,
    required this.pushNotificationSender,
  });

  /// Deterministic numeric Agora uid derived from a Supabase user id
  /// (FNV-1a 32-bit hash, masked into the positive 31-bit range so the
  /// result is safely representable as a Dart `int` on every platform,
  /// including web/JS). This is data-layer plumbing — Agora requires a
  /// numeric uid but the rest of the app only ever deals in Supabase's
  /// string user ids — so it lives here rather than in any domain
  /// contract. Flagged in Phase 1 §6/§25 as needing a collision-resistance
  /// review before production sign-off; not re-litigated here.
  static int agoraUidFromUserId(String userId) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final unit in userId.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    final uid = hash & 0x7FFFFFFF;
    return uid == 0 ? 1 : uid;
  }

  @override
  Future<Either<Failure, CallSessionEntity>> createCall({
    required String calleeId,
    required CallType callType,
  }) async {
    final callerId = supabase.auth.currentUser?.id;
    if (callerId == null) {
      return const Left(CallPermissionFailure('You must be signed in to start a call.'));
    }
    if (callerId == calleeId) {
      return const Left(CallValidationFailure('You cannot call yourself.'));
    }

    final channelName = 'call_${_uuid.v4()}';
    final agoraUidCaller = agoraUidFromUserId(callerId);
    final agoraUidCallee = agoraUidFromUserId(calleeId);

    try {
      final dto = await remoteDataSource.createCallSession(
        callerId: callerId,
        calleeId: calleeId,
        channelName: channelName,
        callType: callType.name,
        agoraUidCaller: agoraUidCaller,
        agoraUidCallee: agoraUidCallee,
      );

      unawaited(remoteDataSource.insertCallEvent(
        callId: dto.id,
        eventType: 'rang',
        actorId: callerId,
      ));

      unawaited(pushNotificationSender.sendChatMessageNotification(
        targetUserId: calleeId,
        title: callType == CallType.video ? 'Incoming video call' : 'Incoming call',
        body: 'Tap to answer',
        data: {
          'type': 'incoming_call',
          'callId': dto.id,
          'callerId': callerId,
          'callType': callType.name,
          'channelName': channelName,
        },
      ));

      return Right(CallSessionModel.fromDto(dto));
    } on PostgrestException catch (e) {
      // Busy-race guard (Open Decision #7 / the DB-level unique partial
      // index from the withdrawn Milestone 1 backend design): a concurrent
      // insert for the same live pair violates the unique index and is
      // rejected here with Postgres code 23505.
      if (e.code == '23505') {
        return const Left(CallRaceLostFailure());
      }
      return Left(UnknownCallFailure(e.message));
    } catch (e) {
      return Left(UnknownCallFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> respondToCall({
    required String callId,
    required CallResponse response,
  }) async {
    final actorId = supabase.auth.currentUser?.id;
    final (String status, String? endReason, String eventType) = switch (response) {
      CallResponse.accept => ('accepted', null, 'accepted'),
      CallResponse.decline => ('declined', 'declined_by_callee', 'declined'),
      CallResponse.busy => ('busy', 'callee_busy', 'busy'),
    };

    try {
      await remoteDataSource.updateCallStatus(callId: callId, status: status, endReason: endReason);
      unawaited(remoteDataSource.insertCallEvent(callId: callId, eventType: eventType, actorId: actorId));
      return const Right(null);
    } on PostgrestException catch (e) {
      return Left(_mapPostgrestFailure(e));
    } catch (e) {
      return Left(UnknownCallFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> cancelCall(String callId) async {
    final actorId = supabase.auth.currentUser?.id;
    try {
      await remoteDataSource.updateCallStatus(
        callId: callId,
        status: 'cancelled',
        endReason: 'cancelled_by_caller',
      );
      unawaited(remoteDataSource.insertCallEvent(callId: callId, eventType: 'cancelled', actorId: actorId));
      return const Right(null);
    } on PostgrestException catch (e) {
      return Left(_mapPostgrestFailure(e));
    } catch (e) {
      return Left(UnknownCallFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> endCall({
    required String callId,
    required String endReason,
  }) async {
    final actorId = supabase.auth.currentUser?.id;
    try {
      await remoteDataSource.updateCallStatus(callId: callId, status: 'ended', endReason: endReason);
      unawaited(remoteDataSource.insertCallEvent(callId: callId, eventType: 'ended', actorId: actorId));
      return const Right(null);
    } on PostgrestException catch (e) {
      return Left(_mapPostgrestFailure(e));
    } catch (e) {
      return Left(UnknownCallFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> markMissed(String callId) async {
    try {
      // MILESTONE 6: fetch-then-check idempotency guard. `markMissed` is
      // now also invoked by `ReconcileStaleCallsUseCase` off a
      // possibly-stale `getCallHistory` snapshot (app resume/cold start,
      // not a live realtime event), so unlike the other write methods
      // here it can legitimately race a real, just-happened accept/decline
      // — this check is what keeps that race from ever overwriting a call
      // that has already moved on. The caller-side ringing-timeout path
      // (`CallCubit.kRingingTimeout`) still only ever calls this while its
      // own state is 'ringing', so this guard is a no-op cost-wise for
      // that existing call site.
      final current = await remoteDataSource.getCallSession(callId);
      if (current == null || current.status != 'ringing') {
        return const Right(null);
      }

      await remoteDataSource.updateCallStatus(callId: callId, status: 'missed', endReason: 'timeout');
      unawaited(remoteDataSource.insertCallEvent(callId: callId, eventType: 'missed'));

      // MILESTONE 6: missed-call push, mirroring the invite push's exact
      // pattern in createCall() — same service, same 'data' shape
      // convention, new 'missed_call' type so a future FCM routing branch
      // (Phase 1 §17, still not built — out of scope here) can eventually
      // distinguish it from 'incoming_call'.
      unawaited(pushNotificationSender.sendChatMessageNotification(
        targetUserId: current.calleeId,
        title: 'Missed call',
        body: 'You missed a call.',
        data: {
          'type': 'missed_call',
          'callId': callId,
          'callerId': current.callerId,
        },
      ));

      return const Right(null);
    } on PostgrestException catch (e) {
      return Left(_mapPostgrestFailure(e));
    } catch (e) {
      return Left(UnknownCallFailure(e.toString()));
    }
  }

  @override
  Stream<CallSessionEntity> watchIncomingCalls(String userId) {
    return realtimeDataSource.subscribeToIncomingCalls(userId).map(CallSessionModel.fromDto);
  }

  @override
  Stream<CallSessionEntity> watchCallStatus(String callId) async* {
    // ROOT-CAUSE FIX (Milestone 7 Part C): subscribeToCallStatus only fires
    // on Postgres UPDATE events, so a fresh 'ringing' row (created via
    // INSERT) never produces an initial event on its own — .first on this
    // stream would otherwise hang until the row is later updated (e.g. the
    // caller cancelling), by which point status is no longer 'ringing'.
    // Seed the stream with the row's current state via the existing
    // getCallSession fetch before switching to live updates, matching the
    // pattern already used by markMissed above.
    final current = await remoteDataSource.getCallSession(callId);
    if (current != null) yield CallSessionModel.fromDto(current);
    yield* realtimeDataSource.subscribeToCallStatus(callId).map(CallSessionModel.fromDto);
  }

  @override
  Future<Either<Failure, CallHistoryPageEntity>> getCallHistory({
    required String userId,
    String? cursor,
    int limit = 20,
  }) async {
    try {
      final dtos = await remoteDataSource.getCallHistory(userId: userId, cursor: cursor, limit: limit);
      final items = dtos.map(CallSessionModel.fromDto).toList();
      final nextCursor = items.length == limit ? items.last.createdAt.toIso8601String() : null;
      return Right(CallHistoryPageEntity(items: items, nextCursor: nextCursor));
    } on PostgrestException catch (e) {
      return Left(UnknownCallFailure(e.message));
    } catch (e) {
      return Left(UnknownCallFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AgoraCredentialsEntity>> getAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  }) async {
    try {
      final dto = await remoteDataSource.fetchAgoraToken(callId: callId, channelName: channelName, uid: uid);
      return Right(AgoraCredentialsEntity(
        appId: dto.appId,
        token: dto.token,
        channelName: dto.channel,
        uid: dto.uid,
        expiresAt: DateTime.parse(dto.expiresAt),
      ));
    } catch (e) {
      return Left(AgoraTokenFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AgoraCredentialsEntity>> refreshAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  }) {
    // Same underlying call as getAgoraToken — kept as a separate method on
    // the interface (Phase 1 §9) purely so call sites/telemetry can
    // distinguish "initial fetch" from "mid-call refresh"; the request
    // itself is identical.
    return getAgoraToken(callId: callId, channelName: channelName, uid: uid);
  }

  Failure _mapPostgrestFailure(PostgrestException e) {
    if (e.code == 'PGRST116') {
      // Postgrest's "no rows found" — the row either never existed or is
      // no longer visible under this user's RLS policy.
      return const CallNotFoundFailure();
    }
    return UnknownCallFailure(e.message);
  }
}
