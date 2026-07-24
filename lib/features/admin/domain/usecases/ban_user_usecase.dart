import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/admin_security_gateway.dart';
import '../entities/ban_type.dart';

class BanUserUseCase {
  final AdminSecurityGateway gateway;
  const BanUserUseCase(this.gateway);

  Future<Either<Failure, void>> call({
    required String targetUid,
    required String reason,
    required String issuedBy,
    required BanType type,
    DateTime? expiresAt,
  }) {
    return gateway.banUser(
      actorUid: issuedBy,
      targetUid: targetUid,
      reason: reason,
      type: type,
      expiresAt: expiresAt,
    );
  }
}
