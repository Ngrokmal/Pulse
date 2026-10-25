import '../../../profile/data/models/profile_model.dart';
import '../../domain/entities/admin_user_record.dart';
import '../../domain/entities/ban_type.dart';

class AdminUserRecordModel extends AdminUserRecord {
  const AdminUserRecordModel({
    required ProfileModel profile,
    super.isBanned,
    super.isDisabled,
    super.banType,
    super.banExpiresAt,
  }) : super(profile: profile);

  factory AdminUserRecordModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String firebaseUid,
  }) {
    final expiresAtRaw = row['ban_expires_at'];
    return AdminUserRecordModel(
      profile: ProfileModel.fromSupabaseRows(uid: firebaseUid, userRow: row),
      isBanned: row['is_banned'] as bool? ?? false,
      isDisabled: row['is_disabled'] as bool? ?? false,
      banType: row['ban_type'] != null ? banTypeFromString(row['ban_type'] as String?) : null,
      banExpiresAt: expiresAtRaw is String ? DateTime.tryParse(expiresAtRaw)?.toLocal() : null,
    );
  }
}
