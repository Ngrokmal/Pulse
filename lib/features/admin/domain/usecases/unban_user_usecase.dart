import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/admin_security_gateway.dart';

class UnbanUserUseCase {
  final AdminSecurityGateway gateway;
  const UnbanUserUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String targetUid, required String issuedBy}) {
    return gateway.unbanUser(actorUid: issuedBy, targetUid: targetUid);
  }
}
