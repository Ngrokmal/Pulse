import 'package:dartz/dartz.dart';
import '../../errors/failures.dart';
import '../../../features/admin/domain/repositories/admin_repository.dart';
import '../../../features/admin/domain/entities/ban_type.dart';
import '../../../features/admin/domain/entities/report_status.dart';
import '../authorization/authorization_failure.dart';
import '../authorization/ban_authorization.dart';
import '../authorization/admin_authorization.dart';

abstract class AdminSecurityGateway {
  Future<Either<Failure, void>> banUser({
    required String actorUid,
    required String targetUid,
    required String reason,
    required BanType type,
    DateTime? expiresAt,
  });

  Future<Either<Failure, void>> unbanUser({
    required String actorUid,
    required String targetUid,
  });

  Future<Either<Failure, void>> disableAccount({
    required String actorUid,
    required String targetUid,
  });

  Future<Either<Failure, void>> restoreAccount({
    required String actorUid,
    required String targetUid,
  });

  Future<Either<Failure, void>> issueWarning({
    required String actorUid,
    required String targetUid,
    required String reason,
  });

  Future<Either<Failure, void>> updateReportStatus({
    required String actorUid,
    required String reportId,
    required ReportStatus status,
  });
}

class LocalAdminSecurityGateway implements AdminSecurityGateway {
  final AdminRepository adminRepository;
  final BanAuthorization banAuthorization;
  final AdminAuthorization adminAuthorization;

  const LocalAdminSecurityGateway({
    required this.adminRepository,
    required this.banAuthorization,
    required this.adminAuthorization,
  });

  @override
  Future<Either<Failure, void>> banUser({
    required String actorUid,
    required String targetUid,
    required String reason,
    required BanType type,
    DateTime? expiresAt,
  }) async {
    final result = await banAuthorization.checkCanBanUser(actorUid: actorUid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return adminRepository.banUser(
      targetUid: targetUid,
      reason: reason,
      issuedBy: actorUid,
      type: type,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<Either<Failure, void>> unbanUser({required String actorUid, required String targetUid}) async {
    final result = await banAuthorization.checkCanUnbanUser(actorUid: actorUid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return adminRepository.unbanUser(targetUid: targetUid, issuedBy: actorUid);
  }

  @override
  Future<Either<Failure, void>> disableAccount({required String actorUid, required String targetUid}) async {
    final result = await banAuthorization.checkCanDisableAccount(actorUid: actorUid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return adminRepository.disableAccount(targetUid: targetUid, issuedBy: actorUid);
  }

  @override
  Future<Either<Failure, void>> restoreAccount({required String actorUid, required String targetUid}) async {
    final result = await banAuthorization.checkCanRestoreAccount(actorUid: actorUid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return adminRepository.restoreAccount(targetUid: targetUid, issuedBy: actorUid);
  }

  @override
  Future<Either<Failure, void>> issueWarning({
    required String actorUid,
    required String targetUid,
    required String reason,
  }) async {
    final result = await adminAuthorization.checkIsAdmin(actorUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return adminRepository.issueWarning(userUid: targetUid, reason: reason, issuedBy: actorUid);
  }

  @override
  Future<Either<Failure, void>> updateReportStatus({
    required String actorUid,
    required String reportId,
    required ReportStatus status,
  }) async {
    final result = await adminAuthorization.checkIsAdmin(actorUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return adminRepository.updateReportStatus(reportId: reportId, status: status, adminUid: actorUid);
  }
}
