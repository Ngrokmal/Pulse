import '../../domain/entities/admin_action_log_entry.dart';

class AdminActionLogModel extends AdminActionLogEntry {
  const AdminActionLogModel({
    required super.logId,
    required super.action,
    required super.actorUid,
    super.targetUid,
    super.reportId,
    super.details,
    required super.timestamp,
  });

  factory AdminActionLogModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String actorUid,
    String? targetUid,
  }) {
    final ts = row['created_at'];
    return AdminActionLogModel(
      logId: row['id'] as String? ?? '',
      action: row['action'] as String? ?? '',
      actorUid: actorUid,
      targetUid: targetUid,
      reportId: row['report_id'] as String?,
      details: row['details'] as String?,
      timestamp: ts is String ? DateTime.parse(ts).toLocal() : DateTime.now(),
    );
  }
}
