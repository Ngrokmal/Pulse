import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/security/gateways/admin_security_gateway.dart';
import '../entities/report_status.dart';

class UpdateReportStatusUseCase {
  final AdminSecurityGateway gateway;
  const UpdateReportStatusUseCase(this.gateway);

  Future<Either<Failure, void>> call({
    required String reportId,
    required ReportStatus status,
    required String adminUid,
  }) {
    return gateway.updateReportStatus(actorUid: adminUid, reportId: reportId, status: status);
  }
}
