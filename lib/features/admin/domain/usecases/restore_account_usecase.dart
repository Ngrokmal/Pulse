import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/admin_security_gateway.dart';

class RestoreAccountUseCase {
  final AdminSecurityGateway gateway;
  const RestoreAccountUseCase(this.gateway);

  Future<Either<Failure, void>> call({required String targetUid, required String issuedBy}) {
    return gateway.restoreAccount(actorUid: issuedBy, targetUid: targetUid);
  }
}
