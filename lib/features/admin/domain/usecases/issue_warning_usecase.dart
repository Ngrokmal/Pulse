import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/admin_security_gateway.dart';

class IssueWarningUseCase {
  final AdminSecurityGateway gateway;
  const IssueWarningUseCase(this.gateway);

  Future<Either<Failure, void>> call({
    required String userUid,
    required String reason,
    required String issuedBy,
  }) {
    return gateway.issueWarning(actorUid: issuedBy, targetUid: userUid, reason: reason);
  }
}
