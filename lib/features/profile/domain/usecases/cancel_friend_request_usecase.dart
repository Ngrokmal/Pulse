import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';

class CancelFriendRequestUseCase {
  final FriendSecurityGateway gateway;
  const CancelFriendRequestUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String uid, required String targetUid}) {
    return gateway.cancelFriendRequest(actorUid: uid, uid: uid, targetUid: targetUid);
  }
}
