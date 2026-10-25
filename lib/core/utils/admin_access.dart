import '../config/admin_config.dart';

class AdminAccess {
  AdminAccess._();

  static bool isAdmin(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return AdminConfig.adminUids.contains(uid);
  }
}
