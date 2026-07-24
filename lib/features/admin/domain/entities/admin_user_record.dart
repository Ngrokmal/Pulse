import '../../../profile/domain/entities/profile_entity.dart';
import 'ban_type.dart';

/// Phase 8.6A (Admin Foundation)
///
/// ProfileEntity/ProfileModel are shared across the whole app and are left
/// untouched (minimum file changes). Moderation flags aren't part of that
/// entity, so this small wrapper carries them alongside a profile for the
/// admin screens only.
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
