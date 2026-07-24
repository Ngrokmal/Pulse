import 'package:cloud_functions/cloud_functions.dart';
import 'package:dartz/dartz.dart';
import '../../errors/failures.dart';
import '../../../features/admin/domain/entities/ban_type.dart';
import '../../../features/admin/domain/entities/report_status.dart';
import 'admin_security_gateway.dart';

class CloudFunctionAdminSecurityGateway implements AdminSecurityGateway {
  final FirebaseFunctions functions;

  const CloudFunctionAdminSecurityGateway({required this.functions});

  Future<Either<Failure, void>> _call(String name, Map<String, dynamic> data) async {
    try {
      await functions.httpsCallable(name).call(data);
      return const Right(null);
    } on FirebaseFunctionsException catch (e) {
      return Left(FirebaseFailure(e.message ?? e.code));
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> banUser({
    required String actorUid,
    required String targetUid,
    required String reason,
    required BanType type,
    DateTime? expiresAt,
  }) {
    return _call('banUser', {
      'targetUid': targetUid,
      'reason': reason,
      'type': banTypeToString(type),
      'expiresAt': expiresAt?.toIso8601String(),
    });
  }

  @override
  Future<Either<Failure, void>> unbanUser({required String actorUid, required String targetUid}) {
    return _call('unbanUser', {'targetUid': targetUid});
  }

  @override
  Future<Either<Failure, void>> disableAccount({required String actorUid, required String targetUid}) {
    return _call('disableAccount', {'targetUid': targetUid});
  }

  @override
  Future<Either<Failure, void>> restoreAccount({required String actorUid, required String targetUid}) {
    return _call('restoreAccount', {'targetUid': targetUid});
  }

  @override
  Future<Either<Failure, void>> issueWarning({
    required String actorUid,
    required String targetUid,
    required String reason,
  }) {
    return _call('issueWarning', {'targetUid': targetUid, 'reason': reason});
  }

  @override
  Future<Either<Failure, void>> updateReportStatus({
    required String actorUid,
    required String reportId,
    required ReportStatus status,
  }) {
    return _call('updateReportStatus', {
      'reportId': reportId,
      'status': reportStatusToString(status),
    });
  }
}
