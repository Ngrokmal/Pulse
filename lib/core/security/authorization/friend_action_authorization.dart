import 'authorization_result.dart';

abstract class FriendActionAuthorization {
  Future<AuthorizationResult> checkCanSendFriendRequest({required String actorUid, required String fromUid, required String toUid});

  Future<AuthorizationResult> checkCanCancelFriendRequest({required String actorUid, required String uid, required String targetUid});

  Future<AuthorizationResult> checkCanAcceptFriendRequest({required String actorUid, required String uid, required String requesterUid});

  Future<AuthorizationResult> checkCanRejectFriendRequest({required String actorUid, required String uid, required String requesterUid});

  Future<AuthorizationResult> checkCanUnfriend({required String actorUid, required String uid, required String targetUid});

  Future<AuthorizationResult> checkCanBlockUser({required String actorUid, required String uid, required String targetUid});

  Future<AuthorizationResult> checkCanUnblockUser({required String actorUid, required String uid, required String targetUid});
}

class LocalFriendActionAuthorization implements FriendActionAuthorization {
  const LocalFriendActionAuthorization();

  AuthorizationResult _requireSelf(String actorUid, String selfUid) {
    if (actorUid != selfUid) {
      return const AuthorizationResult.deny('Actor does not match the acting party.');
    }
    return const AuthorizationResult.allow();
  }

  @override
  Future<AuthorizationResult> checkCanSendFriendRequest({
    required String actorUid,
    required String fromUid,
    required String toUid,
  }) async {
    if (fromUid == toUid) return const AuthorizationResult.deny('Cannot friend-request yourself.');
    return _requireSelf(actorUid, fromUid);
  }

  @override
  Future<AuthorizationResult> checkCanCancelFriendRequest({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    return _requireSelf(actorUid, uid);
  }

  @override
  Future<AuthorizationResult> checkCanAcceptFriendRequest({
    required String actorUid,
    required String uid,
    required String requesterUid,
  }) async {
    return _requireSelf(actorUid, uid);
  }

  @override
  Future<AuthorizationResult> checkCanRejectFriendRequest({
    required String actorUid,
    required String uid,
    required String requesterUid,
  }) async {
    return _requireSelf(actorUid, uid);
  }

  @override
  Future<AuthorizationResult> checkCanUnfriend({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    return _requireSelf(actorUid, uid);
  }

  @override
  Future<AuthorizationResult> checkCanBlockUser({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    if (uid == targetUid) return const AuthorizationResult.deny('Cannot block yourself.');
    return _requireSelf(actorUid, uid);
  }

  @override
  Future<AuthorizationResult> checkCanUnblockUser({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    return _requireSelf(actorUid, uid);
  }
}
