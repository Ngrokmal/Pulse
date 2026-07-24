import '../config/admin_config.dart';

/// Phase 8.6A (Admin Foundation)
///
/// Single choke point for "is this user an admin?" checks. Every admin
/// entry point (navigation + screens) must go through this so the rule
/// only ever lives in one place.
class AdminAccess {
  AdminAccess._();

  static bool isAdmin(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return AdminConfig.adminUids.contains(uid);
  }
}
