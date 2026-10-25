import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';

class AcceptFriendRequestUseCase {
  final FriendSecurityGateway gateway;
  const AcceptFriendRequestUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String uid, required String requesterUid}) {
    return gateway.acceptFriendRequest(actorUid: uid, uid: uid, requesterUid: requesterUid);
  }
}
