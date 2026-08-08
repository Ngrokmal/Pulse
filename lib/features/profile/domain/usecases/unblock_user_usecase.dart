import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';

class UnblockUserUseCase {
  final FriendSecurityGateway gateway;
  const UnblockUserUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String uid, required String targetUid}) {
    return gateway.unblockUser(actorUid: uid, uid: uid, targetUid: targetUid);
  }
}
