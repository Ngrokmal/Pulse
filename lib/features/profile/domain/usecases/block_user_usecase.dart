import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';

class BlockUserUseCase {
  final FriendSecurityGateway gateway;
  const BlockUserUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String uid, required String targetUid}) {
    return gateway.blockUser(actorUid: uid, uid: uid, targetUid: targetUid);
  }
}
