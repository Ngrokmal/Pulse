import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/friend_security_gateway.dart';

class UnfriendUseCase {
  final FriendSecurityGateway gateway;
  const UnfriendUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String uid, required String targetUid}) {
    return gateway.unfriend(actorUid: uid, uid: uid, targetUid: targetUid);
  }
}
