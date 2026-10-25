import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../profile/domain/entities/friend_request_status.dart';
import '../../../profile/domain/repositories/friend_repository.dart';
import '../entities/call_session_entity.dart';
import '../entities/call_type.dart';
import '../failures/call_failures.dart';
import '../repositories/call_repository.dart';

/// Caller taps the call button. Validates the callee is a friend by
/// reading the existing, unmodified `FriendRepository` (read-only —
/// Phase 1 §4.3/§11, "call module never touches FCM/friend internals
/// beyond this read"), then delegates persistence + push to
/// [CallRepository.createCall].
///
/// Already-in-a-call / busy-race validation happens server-side (RLS +
/// the DB-level unique partial index, Open Decision #7) and is surfaced
/// back through [CallRepository.createCall]'s own failure — this usecase
/// does not duplicate that check client-side.
class InitiateCallUseCase {
  final CallRepository callRepository;
  final FriendRepository friendRepository;

  const InitiateCallUseCase({
    required this.callRepository,
    required this.friendRepository,
  });

  Future<Either<Failure, CallSessionEntity>> call({
    required String viewerUid,
    required String calleeId,
    required CallType callType,
  }) async {
    final statusResult = await friendRepository.getFriendRequestStatus(
      viewerUid: viewerUid,
      profileUid: calleeId,
    );

    Failure? statusFailure;
    FriendRequestStatus? status;
    statusResult.fold((f) => statusFailure = f, (s) => status = s);

    if (statusFailure != null) {
      return Left(statusFailure!);
    }
    if (status != FriendRequestStatus.friends) {
      return const Left(CallNotFriendFailure());
    }

    return callRepository.createCall(calleeId: calleeId, callType: callType);
  }
}
