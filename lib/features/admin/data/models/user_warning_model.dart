import '../../domain/entities/user_warning.dart';

class UserWarningModel extends UserWarning {
  const UserWarningModel({
    required super.warningId,
    required super.userUid,
    required super.reason,
    required super.timestamp,
    required super.issuedBy,
  });

  factory UserWarningModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String userUid,
    required String issuedBy,
  }) {
    final ts = row['created_at'];
    return UserWarningModel(
      warningId: row['id'] as String? ?? '',
      userUid: userUid,
      reason: row['reason'] as String? ?? '',
      timestamp: ts is String ? DateTime.parse(ts).toLocal() : DateTime.now(),
      issuedBy: issuedBy,
    );
  }
}
