import 'security_operation.dart';
import 'security_operation_spec.dart';

const List<SecurityOperationSpec> kSecurityOperationRegistry = [
  SecurityOperationSpec(
    operation: SecurityOperation.sendFriendRequest,
    currentImplementationPath:
        'lib/features/profile/data/repositories/friend_repository_impl.dart#sendFriendRequest',
    crossUserWrite: true,
    crossUserRead: true,
    collectionsWritten: ['users/{fromUid}/friendRequests', 'users/{toUid}/friendRequests'],
    collectionsRead: ['users/{toUid}/blocked', 'users/{fromUid}/blocked', 'users/{toUid}', 'users/*/friends'],
    plannedCloudFunctionName: 'sendFriendRequest',
    risk: SecurityOperationRisk.critical,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.acceptFriendRequest,
    currentImplementationPath:
        'lib/features/profile/data/repositories/friend_repository_impl.dart#acceptFriendRequest',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: [
      'users/{uid}/friendRequests',
      'users/{requesterUid}/friendRequests',
      'users/{uid}/friends',
      'users/{requesterUid}/friends',
      'users/{uid}',
      'users/{requesterUid}',
    ],
    collectionsRead: [],
    plannedCloudFunctionName: 'acceptFriendRequest',
    risk: SecurityOperationRisk.critical,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.rejectFriendRequest,
    currentImplementationPath:
        'lib/features/profile/data/repositories/friend_repository_impl.dart#rejectFriendRequest',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: ['users/{uid}/friendRequests', 'users/{requesterUid}/friendRequests'],
    collectionsRead: [],
    plannedCloudFunctionName: 'rejectFriendRequest',
    risk: SecurityOperationRisk.high,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.cancelFriendRequest,
    currentImplementationPath:
        'lib/features/profile/data/repositories/friend_repository_impl.dart#cancelFriendRequest',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: ['users/{uid}/friendRequests', 'users/{targetUid}/friendRequests'],
    collectionsRead: [],
    plannedCloudFunctionName: 'cancelFriendRequest',
    risk: SecurityOperationRisk.high,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.unfriend,
    currentImplementationPath: 'lib/features/profile/data/repositories/friend_repository_impl.dart#unfriend',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: ['users/{uid}/friends', 'users/{targetUid}/friends', 'users/{uid}', 'users/{targetUid}'],
    collectionsRead: [],
    plannedCloudFunctionName: 'unfriend',
    risk: SecurityOperationRisk.high,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.blockUser,
    currentImplementationPath: 'lib/features/profile/data/repositories/friend_repository_impl.dart#blockUser',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: [
      'users/{uid}/blocked',
      'users/{uid}/friends',
      'users/{targetUid}/friends',
      'users/{uid}/friendRequests',
      'users/{targetUid}/friendRequests',
      'users/{uid}',
      'users/{targetUid}',
    ],
    collectionsRead: [],
    plannedCloudFunctionName: 'blockUser',
    risk: SecurityOperationRisk.critical,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.unblockUser,
    currentImplementationPath: 'lib/features/profile/data/repositories/friend_repository_impl.dart#unblockUser',
    crossUserWrite: false,
    crossUserRead: false,
    collectionsWritten: ['users/{uid}/blocked'],
    collectionsRead: [],
    plannedCloudFunctionName: 'unblockUser',
    risk: SecurityOperationRisk.medium,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.banUser,
    currentImplementationPath: 'lib/features/admin/data/repositories/admin_repository_impl.dart#banUser',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: ['bans', 'users/{targetUid}', 'adminActionLog'],
    collectionsRead: [],
    plannedCloudFunctionName: 'banUser',
    risk: SecurityOperationRisk.critical,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.unbanUser,
    currentImplementationPath: 'lib/features/admin/data/repositories/admin_repository_impl.dart#unbanUser',
    crossUserWrite: true,
    crossUserRead: true,
    collectionsWritten: ['bans', 'users/{targetUid}', 'adminActionLog'],
    collectionsRead: ['bans'],
    plannedCloudFunctionName: 'unbanUser',
    risk: SecurityOperationRisk.critical,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.disableAccount,
    currentImplementationPath: 'lib/features/admin/data/repositories/admin_repository_impl.dart#disableAccount',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: ['users/{targetUid}', 'adminActionLog'],
    collectionsRead: [],
    plannedCloudFunctionName: 'disableAccount',
    risk: SecurityOperationRisk.critical,
  ),
  SecurityOperationSpec(
    operation: SecurityOperation.restoreAccount,
    currentImplementationPath: 'lib/features/admin/data/repositories/admin_repository_impl.dart#restoreAccount',
    crossUserWrite: true,
    crossUserRead: false,
    collectionsWritten: ['users/{targetUid}', 'adminActionLog'],
    collectionsRead: [],
    plannedCloudFunctionName: 'restoreAccount',
    risk: SecurityOperationRisk.critical,
  ),
];

SecurityOperationSpec? findSecurityOperationSpec(SecurityOperation operation) {
  for (final spec in kSecurityOperationRegistry) {
    if (spec.operation == operation) return spec;
  }
  return null;
}
