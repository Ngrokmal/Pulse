import 'report_status.dart';
import 'report_type.dart';

class ModerationReport {
  final String reportId;
  final ReportType type;
  final String reporterUid;
  final String? targetUid;
  final String? messageId;
  final String? chatId;
  final String? groupId;
  final String reason;
  final String? description;
  final DateTime timestamp;
  final ReportStatus status;

  const ModerationReport({
    required this.reportId,
    required this.type,
    required this.reporterUid,
    this.targetUid,
    this.messageId,
    this.chatId,
    this.groupId,
    required this.reason,
    this.description,
    required this.timestamp,
    this.status = ReportStatus.pending,
  });
}
