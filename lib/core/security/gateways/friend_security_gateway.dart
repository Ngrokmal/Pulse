import 'package:dartz/dartz.dart';
import '../../errors/failures.dart';
import '../../../features/profile/domain/repositories/friend_repository.dart';
import '../authorization/authorization_failure.dart';
import '../authorization/friend_action_authorization.dart';

/// Method signatures mirror FriendRepository exactly so a future
/// FirebaseFunctions-backed implementation is a drop-in replacement for
/// LocalFriendSecurityGateway wherever this interface is depended on.
abstract class FriendSecurityGateway {
  Future<Either<Failure, void>> sendFriendRequest({required String actorUid, required String fromUid, required String toUid});

  Future<Either<Failure, void>> cancelFriendRequest({required String actorUid, required String uid, required String targetUid});

  Future<Either<Failure, void>> acceptFriendRequest({required String actorUid, required String uid, required String requesterUid});

  Future<Either<Failure, void>> rejectFriendRequest({required String actorUid, required String uid, required String requesterUid});

  Future<Either<Failure, void>> unfriend({required String actorUid, required String uid, required String targetUid});

  Future<Either<Failure, void>> blockUser({required String actorUid, required String uid, required String targetUid});

  Future<Either<Failure, void>> unblockUser({required String actorUid, required String uid, required String targetUid});
}

class LocalFriendSecurityGateway implements FriendSecurityGateway {
  final FriendRepository friendRepository;
  final FriendActionAuthorization friendActionAuthorization;

  const LocalFriendSecurityGateway({required this.friendRepository, required this.friendActionAuthorization});

  @override
  Future<Either<Failure, void>> sendFriendRequest({
    required String actorUid,
    required String fromUid,
    required String toUid,
  }) async {
    final result = await friendActionAuthorization.checkCanSendFriendRequest(
      actorUid: actorUid,
      fromUid: fromUid,
      toUid: toUid,
    );
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.sendFriendRequest(fromUid: fromUid, toUid: toUid);
  }

  @override
  Future<Either<Failure, void>> cancelFriendRequest({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    final result = await friendActionAuthorization.checkCanCancelFriendRequest(
      actorUid: actorUid,
      uid: uid,
      targetUid: targetUid,
    );
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.cancelFriendRequest(uid: uid, targetUid: targetUid);
  }

  @override
  Future<Either<Failure, void>> acceptFriendRequest({
    required String actorUid,
    required String uid,
    required String requesterUid,
  }) async {
    final result = await friendActionAuthorization.checkCanAcceptFriendRequest(
      actorUid: actorUid,
      uid: uid,
      requesterUid: requesterUid,
    );
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.acceptFriendRequest(uid: uid, requesterUid: requesterUid);
  }

  @override
  Future<Either<Failure, void>> rejectFriendRequest({
    required String actorUid,
    required String uid,
    required String requesterUid,
  }) async {
    final result = await friendActionAuthorization.checkCanRejectFriendRequest(
      actorUid: actorUid,
      uid: uid,
      requesterUid: requesterUid,
    );
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.rejectFriendRequest(uid: uid, requesterUid: requesterUid);
  }

  @override
  Future<Either<Failure, void>> unfriend({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    final result = await friendActionAuthorization.checkCanUnfriend(actorUid: actorUid, uid: uid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.unfriend(uid: uid, targetUid: targetUid);
  }

  @override
  Future<Either<Failure, void>> blockUser({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    final result = await friendActionAuthorization.checkCanBlockUser(actorUid: actorUid, uid: uid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.blockUser(uid: uid, targetUid: targetUid);
  }

  @override
  Future<Either<Failure, void>> unblockUser({
    required String actorUid,
    required String uid,
    required String targetUid,
  }) async {
    final result = await friendActionAuthorization.checkCanUnblockUser(actorUid: actorUid, uid: uid, targetUid: targetUid);
    if (!result.allowed) return Left(AuthorizationFailure(result.reason ?? 'Not authorized.'));
    return friendRepository.unblockUser(uid: uid, targetUid: targetUid);
  }
}
