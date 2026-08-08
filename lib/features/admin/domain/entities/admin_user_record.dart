import '../../../profile/domain/entities/profile_entity.dart';
import 'ban_type.dart';

class AdminUserRecord {
  final ProfileEntity profile;
  final bool isBanned;
  final bool isDisabled;
  final BanType? banType;
  final DateTime? banExpiresAt;

  const AdminUserRecord({
    required this.profile,
    this.isBanned = false,
    this.isDisabled = false,
    this.banType,
    this.banExpiresAt,
  });
}
