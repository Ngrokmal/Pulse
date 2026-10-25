import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/admin_security_gateway.dart';

class DisableAccountUseCase {
  final AdminSecurityGateway gateway;
  const DisableAccountUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String targetUid, required String issuedBy}) {
    return gateway.disableAccount(actorUid: issuedBy, targetUid: targetUid);
  }
}
