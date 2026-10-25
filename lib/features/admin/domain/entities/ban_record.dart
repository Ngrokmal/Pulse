import 'ban_status.dart';
import 'ban_type.dart';

class BanRecord {
  final String banId;
  final String targetUid;
  final String reason;
  final String issuedBy;
  final DateTime timestamp;
  final BanStatus status;
  final BanType type;
  final DateTime? expiresAt;

  const BanRecord({
    required this.banId,
    required this.targetUid,
    required this.reason,
    required this.issuedBy,
    required this.timestamp,
    required this.status,
    required this.type,
    this.expiresAt,
  });

  bool get isExpired {
    if (type != BanType.temporary || expiresAt == null) return false;
    return expiresAt!.isBefore(DateTime.now());
  }

  bool get isCurrentlyActive => status == BanStatus.active && !isExpired;
}
