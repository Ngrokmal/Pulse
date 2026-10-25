import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';

class RejectFriendRequestUseCase {
  final FriendSecurityGateway gateway;
  const RejectFriendRequestUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String uid, required String requesterUid}) {
    return gateway.rejectFriendRequest(actorUid: uid, uid: uid, requesterUid: requesterUid);
  }
}
