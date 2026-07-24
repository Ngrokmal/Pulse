class AdminActionLogEntry {
  final String logId;
  final String action;
  final String actorUid;
  final String? targetUid;
  final String? reportId;
  final String? details;
  final DateTime timestamp;

  const AdminActionLogEntry({
    required this.logId,
    required this.action,
    required this.actorUid,
    this.targetUid,
    this.reportId,
    this.details,
    required this.timestamp,
  });
}
