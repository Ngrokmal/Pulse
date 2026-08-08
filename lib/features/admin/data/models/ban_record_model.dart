import '../../domain/entities/ban_record.dart';
import '../../domain/entities/ban_status.dart';
import '../../domain/entities/ban_type.dart';

class BanRecordModel extends BanRecord {
  const BanRecordModel({
    required super.banId,
    required super.targetUid,
    required super.reason,
    required super.issuedBy,
    required super.timestamp,
    required super.status,
    required super.type,
    super.expiresAt,
  });

  factory BanRecordModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String targetUid,
    required String issuedBy,
  }) {
    final ts = row['created_at'];
    final expiresAtRaw = row['expires_at'];
    return BanRecordModel(
      banId: row['id'] as String? ?? '',
      targetUid: targetUid,
      reason: row['reason'] as String? ?? '',
      issuedBy: issuedBy,
      timestamp: ts is String ? DateTime.parse(ts).toLocal() : DateTime.now(),
      status: banStatusFromString(row['status'] as String?),
      type: banTypeFromString(row['type'] as String?),
      expiresAt: expiresAtRaw is String ? DateTime.parse(expiresAtRaw).toLocal() : null,
    );
  }
}
