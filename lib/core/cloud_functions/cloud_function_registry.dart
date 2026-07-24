import 'cloud_function_operation.dart';
import 'cloud_function_spec.dart';

/// Design-time mapping of Friend Actions, Admin Actions, and Moderation
/// Actions to their future Cloud Functions.
///
/// This registry does not create, deploy, or call any Cloud Function. It
/// exists solely to record, per operation, the future function name, the
/// collections it will touch, its expected auth requirement, and its
/// expected validation requirements, so that Phase 9.0E's follow-up work
/// (actual Cloud Function implementation) has an agreed starting point.
const List<CloudFunctionSpec> kCloudFunctionRegistry = [
  // ---- Friend Actions ----
  CloudFunctionSpec(
    operation: CloudFunctionOperation.sendFriendRequest,
    category: CloudFunctionCategory.friendAction,
    futureFunctionName: 'sendFriendRequest',
    authRequirement: CloudFunctionAuthRequirement.authenticatedSelf,
    collectionsRead: [
      'users/{toUid}/blocked',
      'users/{fromUid}/blocked',
      'users/{toUid}',
      'users/*/friends',
    ],
    collectionsWritten: [
      'users/{fromUid}/friendRequests',
      'users/{toUid}/friendRequests',
    ],
    validationRequirements: [
      'fromUid must not equal toUid',
      'caller uid must equal fromUid',
      'toUid must exist',
      'neither party has blocked the other',
      'parties are not already friends',
      'no existing pending request between the same pair',
    ],
    correspondingSecurityOperationId: 'send_friend_request',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.acceptFriendRequest,
    category: CloudFunctionCategory.friendAction,
    futureFunctionName: 'acceptFriendRequest',
    authRequirement: CloudFunctionAuthRequirement.authenticatedSelf,
    collectionsRead: [],
    collectionsWritten: [
      'users/{uid}/friendRequests',
      'users/{requesterUid}/friendRequests',
      'users/{uid}/friends',
      'users/{requesterUid}/friends',
      'users/{uid}',
      'users/{requesterUid}',
    ],
    validationRequirements: [
      'caller uid must equal uid',
      'a pending friend request from requesterUid to uid must exist',
    ],
    correspondingSecurityOperationId: 'accept_friend_request',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.rejectFriendRequest,
    category: CloudFunctionCategory.friendAction,
    futureFunctionName: 'rejectFriendRequest',
    authRequirement: CloudFunctionAuthRequirement.authenticatedSelf,
    collectionsRead: [],
    collectionsWritten: [
      'users/{uid}/friendRequests',
      'users/{requesterUid}/friendRequests',
    ],
    validationRequirements: [
      'caller uid must equal uid',
      'a pending friend request from requesterUid to uid must exist',
    ],
    correspondingSecurityOperationId: 'reject_friend_request',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.cancelFriendRequest,
    category: CloudFunctionCategory.friendAction,
    futureFunctionName: 'cancelFriendRequest',
    authRequirement: CloudFunctionAuthRequirement.authenticatedSelf,
    collectionsRead: [],
    collectionsWritten: [
      'users/{uid}/friendRequests',
      'users/{targetUid}/friendRequests',
    ],
    validationRequirements: [
      'caller uid must equal uid',
      'a pending friend request from uid to targetUid must exist',
    ],
    correspondingSecurityOperationId: 'cancel_friend_request',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.unfriend,
    category: CloudFunctionCategory.friendAction,
    futureFunctionName: 'unfriend',
    authRequirement: CloudFunctionAuthRequirement.authenticatedSelf,
    collectionsRead: [],
    collectionsWritten: [
      'users/{uid}/friends',
      'users/{targetUid}/friends',
      'users/{uid}',
      'users/{targetUid}',
    ],
    validationRequirements: [
      'caller uid must equal uid',
      'uid and targetUid must currently be friends',
    ],
    correspondingSecurityOperationId: 'unfriend',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.blockUser,
    category: CloudFunctionCategory.friendAction,
    futureFunctionName: 'blockUser',
    authRequirement: CloudFunctionAuthRequirement.authenticatedSelf,
    collectionsRead: [],
    collectionsWritten: [
      'users/{uid}/blocked',
      'users/{uid}/friends',
      'users/{targetUid}/friends',
      'users/{uid}/friendRequests',
      'users/{targetUid}/friendRequests',
      'users/{uid}',
      'users/{targetUid}',
    ],
    validationRequirements: [
      'caller uid must equal uid',
      'uid must not equal targetUid',
      'targetUid must exist',
    ],
    correspondingSecurityOperationId: 'block_user',
  ),

  // ---- Moderation Actions ----
  CloudFunctionSpec(
    operation: CloudFunctionOperation.banUser,
    category: CloudFunctionCategory.moderationAction,
    futureFunctionName: 'banUser',
    authRequirement: CloudFunctionAuthRequirement.authenticatedAdmin,
    collectionsRead: [],
    collectionsWritten: [
      'bans',
      'users/{targetUid}',
      'adminActionLog',
    ],
    validationRequirements: [
      'caller uid must be an admin',
      'caller uid must not equal targetUid',
      'targetUid must exist',
      'targetUid must not already be banned',
    ],
    correspondingSecurityOperationId: 'ban_user',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.unbanUser,
    category: CloudFunctionCategory.moderationAction,
    futureFunctionName: 'unbanUser',
    authRequirement: CloudFunctionAuthRequirement.authenticatedAdmin,
    collectionsRead: ['bans'],
    collectionsWritten: [
      'bans',
      'users/{targetUid}',
      'adminActionLog',
    ],
    validationRequirements: [
      'caller uid must be an admin',
      'caller uid must not equal targetUid',
      'an active ban record for targetUid must exist',
    ],
    correspondingSecurityOperationId: 'unban_user',
  ),

  // ---- Admin Actions ----
  CloudFunctionSpec(
    operation: CloudFunctionOperation.disableAccount,
    category: CloudFunctionCategory.adminAction,
    futureFunctionName: 'disableAccount',
    authRequirement: CloudFunctionAuthRequirement.authenticatedAdmin,
    collectionsRead: [],
    collectionsWritten: [
      'users/{targetUid}',
      'adminActionLog',
    ],
    validationRequirements: [
      'caller uid must be an admin',
      'caller uid must not equal targetUid',
      'targetUid must exist',
      'targetUid account must not already be disabled',
    ],
    correspondingSecurityOperationId: 'disable_account',
  ),
  CloudFunctionSpec(
    operation: CloudFunctionOperation.restoreAccount,
    category: CloudFunctionCategory.adminAction,
    futureFunctionName: 'restoreAccount',
    authRequirement: CloudFunctionAuthRequirement.authenticatedAdmin,
    collectionsRead: [],
    collectionsWritten: [
      'users/{targetUid}',
      'adminActionLog',
    ],
    validationRequirements: [
      'caller uid must be an admin',
      'caller uid must not equal targetUid',
      'targetUid must exist',
      'targetUid account must currently be disabled',
    ],
    correspondingSecurityOperationId: 'restore_account',
  ),
];

CloudFunctionSpec? findCloudFunctionSpec(CloudFunctionOperation operation) {
  for (final spec in kCloudFunctionRegistry) {
    if (spec.operation == operation) return spec;
  }
  return null;
}

List<CloudFunctionSpec> cloudFunctionSpecsForCategory(CloudFunctionCategory category) {
  return kCloudFunctionRegistry.where((spec) => spec.category == category).toList();
}
