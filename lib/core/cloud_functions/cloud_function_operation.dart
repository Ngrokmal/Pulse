/// Design-time enum for Phase 9.0E.
///
/// These operations do not call any Cloud Function yet. They exist so
/// future Cloud Function migration work has a fixed, named target to map
/// against. This file introduces no runtime behavior change.
enum CloudFunctionOperation {
  sendFriendRequest,
  acceptFriendRequest,
  rejectFriendRequest,
  cancelFriendRequest,
  unfriend,
  blockUser,
  banUser,
  unbanUser,
  disableAccount,
  restoreAccount,
}

/// Groups each operation under the action family it belongs to.
enum CloudFunctionCategory {
  friendAction,
  adminAction,
  moderationAction,
}

/// The auth posture the future Cloud Function is expected to require.
enum CloudFunctionAuthRequirement {
  /// Caller must be authenticated and must be the acting party itself.
  authenticatedSelf,

  /// Caller must be authenticated and must be an admin.
  authenticatedAdmin,
}

extension CloudFunctionOperationName on CloudFunctionOperation {
  String get id {
    switch (this) {
      case CloudFunctionOperation.sendFriendRequest:
        return 'send_friend_request';
      case CloudFunctionOperation.acceptFriendRequest:
        return 'accept_friend_request';
      case CloudFunctionOperation.rejectFriendRequest:
        return 'reject_friend_request';
      case CloudFunctionOperation.cancelFriendRequest:
        return 'cancel_friend_request';
      case CloudFunctionOperation.unfriend:
        return 'unfriend';
      case CloudFunctionOperation.blockUser:
        return 'block_user';
      case CloudFunctionOperation.banUser:
        return 'ban_user';
      case CloudFunctionOperation.unbanUser:
        return 'unban_user';
      case CloudFunctionOperation.disableAccount:
        return 'disable_account';
      case CloudFunctionOperation.restoreAccount:
        return 'restore_account';
    }
  }
}
