import '../../utils/admin_access.dart';
import 'authorization_result.dart';

abstract class AdminAuthorization {
  Future<AuthorizationResult> checkIsAdmin(String actorUid);
}

class LocalAdminAuthorization implements AdminAuthorization {
  const LocalAdminAuthorization();

  @override
  Future<AuthorizationResult> checkIsAdmin(String actorUid) async {
    if (AdminAccess.isAdmin(actorUid)) {
      return const AuthorizationResult.allow();
    }
    return const AuthorizationResult.deny('Actor is not an admin.');
  }
}
