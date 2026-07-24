import 'admin_authorization.dart';
import 'authorization_result.dart';

abstract class BanAuthorization {
  Future<AuthorizationResult> checkCanBanUser({required String actorUid, required String targetUid});

  Future<AuthorizationResult> checkCanUnbanUser({required String actorUid, required String targetUid});

  Future<AuthorizationResult> checkCanDisableAccount({required String actorUid, required String targetUid});

  Future<AuthorizationResult> checkCanRestoreAccount({required String actorUid, required String targetUid});
}

class LocalBanAuthorization implements BanAuthorization {
  final AdminAuthorization adminAuthorization;

  const LocalBanAuthorization({required this.adminAuthorization});

  Future<AuthorizationResult> _requireAdmin(String actorUid, String targetUid) async {
    if (actorUid == targetUid) {
      return const AuthorizationResult.deny('Actor cannot target themselves.');
    }
    return adminAuthorization.checkIsAdmin(actorUid);
  }

  @override
  Future<AuthorizationResult> checkCanBanUser({required String actorUid, required String targetUid}) {
    return _requireAdmin(actorUid, targetUid);
  }

  @override
  Future<AuthorizationResult> checkCanUnbanUser({required String actorUid, required String targetUid}) {
    return _requireAdmin(actorUid, targetUid);
  }

  @override
  Future<AuthorizationResult> checkCanDisableAccount({required String actorUid, required String targetUid}) {
    return _requireAdmin(actorUid, targetUid);
  }

  @override
  Future<AuthorizationResult> checkCanRestoreAccount({required String actorUid, required String targetUid}) {
    return _requireAdmin(actorUid, targetUid);
  }
}
