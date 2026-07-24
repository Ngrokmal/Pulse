enum SecurityOperation {
  sendFriendRequest,
  acceptFriendRequest,
  rejectFriendRequest,
  cancelFriendRequest,
  unfriend,
  blockUser,
  unblockUser,
  banUser,
  unbanUser,
  disableAccount,
  restoreAccount,
}

enum SecurityOperationRisk {
  critical,
  high,
  medium,
}

enum SecurityMigrationStatus {
  clientSideOnly,
  cloudFunctionPending,
  cloudFunctionMigrated,
}

extension SecurityOperationName on SecurityOperation {
  String get id {
    switch (this) {
      case SecurityOperation.sendFriendRequest:
        return 'send_friend_request';
      case SecurityOperation.acceptFriendRequest:
        return 'accept_friend_request';
      case SecurityOperation.rejectFriendRequest:
        return 'reject_friend_request';
      case SecurityOperation.cancelFriendRequest:
        return 'cancel_friend_request';
      case SecurityOperation.unfriend:
        return 'unfriend';
      case SecurityOperation.blockUser:
        return 'block_user';
      case SecurityOperation.unblockUser:
        return 'unblock_user';
      case SecurityOperation.banUser:
        return 'ban_user';
      case SecurityOperation.unbanUser:
        return 'unban_user';
      case SecurityOperation.disableAccount:
        return 'disable_account';
      case SecurityOperation.restoreAccount:
        return 'restore_account';
    }
  }
}
