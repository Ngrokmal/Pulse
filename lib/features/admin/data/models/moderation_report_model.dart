import 'dart:convert';
import '../../domain/entities/moderation_report.dart';
import '../../domain/entities/report_status.dart';
import '../../domain/entities/report_type.dart';

class ModerationReportModel extends ModerationReport {
  const ModerationReportModel({
    required super.reportId,
    required super.type,
    required super.reporterUid,
    super.targetUid,
    super.messageId,
    super.chatId,
    super.groupId,
    required super.reason,
    super.description,
    required super.timestamp,
    super.status,
  });

  static Map<String, dynamic> encodeDetails({String? description, String? chatId}) {
    return {
      if (description != null) 'description': description,
      if (chatId != null) 'chatId': chatId,
    };
  }

  factory ModerationReportModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String reporterUid,
    String? targetUid,
  }) {
    final type = reportTypeFromString(row['target_type'] as String?);
    final targetId = row['target_id'] as String?;

    Map<String, dynamic> extra = const {};
    final detailsRaw = row['details'] as String?;
    if (detailsRaw != null && detailsRaw.isNotEmpty) {
      try {
        extra = jsonDecode(detailsRaw) as Map<String, dynamic>;
      } catch (_) {}
    }

    final ts = row['updated_at'] ?? row['created_at'];
    return ModerationReportModel(
      reportId: row['id'] as String? ?? '',
      type: type,
      reporterUid: reporterUid,
      targetUid: type == ReportType.user ? targetUid : null,
      messageId: type == ReportType.message ? targetId : null,
      chatId: type == ReportType.message ? extra['chatId'] as String? : null,
      groupId: type == ReportType.group ? targetId : null,
      reason: row['reason'] as String? ?? '',
      description: extra['description'] as String?,
      timestamp: ts is String ? DateTime.parse(ts).toLocal() : DateTime.now(),
      status: reportStatusFromColumn(row['status'] as String?),
    );
  }
}

ReportStatus reportStatusFromColumn(String? column) {
  switch (column) {
    case 'reviewing':
      return ReportStatus.reviewed;
    case 'resolved':
    case 'dismissed':
      return ReportStatus.resolved;
    case 'open':
    default:
      return ReportStatus.pending;
  }
}

String reportStatusToColumn(ReportStatus status) {
  switch (status) {
    case ReportStatus.pending:
      return 'open';
    case ReportStatus.reviewed:
      return 'reviewing';
    case ReportStatus.resolved:
      return 'resolved';
  }
}
