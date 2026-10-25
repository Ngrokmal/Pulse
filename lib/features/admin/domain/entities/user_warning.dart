class UserWarning {
  final String warningId;
  final String userUid;
  final String reason;
  final DateTime timestamp;
  final String issuedBy;

  const UserWarning({
    required this.warningId,
    required this.userUid,
    required this.reason,
    required this.timestamp,
    required this.issuedBy,
  });
}
