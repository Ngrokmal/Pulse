import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/admin_action_log_entry.dart';
import '../entities/admin_dashboard_stats.dart';
import '../entities/admin_user_record.dart';
import '../entities/ban_record.dart';
import '../entities/ban_type.dart';
import '../entities/moderation_report.dart';
import '../entities/report_status.dart';
import '../entities/user_warning.dart';

abstract class AdminRepository {
  Future<Either<Failure, AdminDashboardStats>> getDashboardStats();

  Future<Either<Failure, AdminUserRecord?>> lookupUserByUid(String uid);

  Future<Either<Failure, List<AdminUserRecord>>> lookupUsersByUsername(String query);

  // Phase 8.6C (Ban System)
  Future<Either<Failure, void>> banUser({
    required String targetUid,
    required String reason,
    required String issuedBy,
    required BanType type,
    DateTime? expiresAt,
  });

  Future<Either<Failure, void>> unbanUser({
    required String targetUid,
    required String issuedBy,
  });

  Future<Either<Failure, void>> disableAccount({
    required String targetUid,
    required String issuedBy,
  });

  Future<Either<Failure, void>> restoreAccount({
    required String targetUid,
    required String issuedBy,
  });

  Future<Either<Failure, List<BanRecord>>> getBanHistory(String targetUid);

  // Phase 8.6B (Moderation System)
  Future<Either<Failure, void>> reportUser({
    required String reporterUid,
    required String targetUid,
    required String reason,
    String? description,
  });

  Future<Either<Failure, void>> reportMessage({
    required String reporterUid,
    required String messageId,
    required String chatId,
    required String reason,
  });

  Future<Either<Failure, void>> reportGroup({
    required String reporterUid,
    required String groupId,
    required String reason,
  });

  Future<Either<Failure, List<ModerationReport>>> getModerationReports();

  Future<Either<Failure, void>> updateReportStatus({
    required String reportId,
    required ReportStatus status,
    required String adminUid,
  });

  Future<Either<Failure, void>> issueWarning({
    required String userUid,
    required String reason,
    required String issuedBy,
  });

  Future<Either<Failure, List<UserWarning>>> getUserWarnings(String userUid);

  Future<Either<Failure, List<AdminActionLogEntry>>> getActionLog();
}
