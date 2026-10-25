import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';
import '../../../../core/utils/moderation_guard.dart';

class FriendRequestRateLimitedFailure extends Failure {
  const FriendRequestRateLimitedFailure()
      : super('You are sending requests too quickly. Please wait a moment and try again.');
}

class SendFriendRequestUseCase {
  final FriendSecurityGateway gateway;
  final ModerationGuard moderationGuard;
  const SendFriendRequestUseCase(this.gateway, this.moderationGuard);

  static const Duration _cooldown = Duration(seconds: 2);
  static final Map<String, DateTime> _lastRequestAt = {};

  Future<Either<Failure, void>> call({required String fromUid, required String toUid}) async {
    try {
      await moderationGuard.ensureNotBlocked(fromUid);
    } on ModerationBlockedException catch (e) {
      return Left(ModerationBlockedFailure(e.message));
    }

    final now = DateTime.now();
    final last = _lastRequestAt[fromUid];
    if (last != null && now.difference(last) < _cooldown) {
      return const Left(FriendRequestRateLimitedFailure());
    }
    _lastRequestAt[fromUid] = now;
    return gateway.sendFriendRequest(actorUid: fromUid, fromUid: fromUid, toUid: toUid);
  }
}
