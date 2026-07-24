import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/friend_request_status.dart';

abstract class FriendRepository {
  Future<Either<Failure, FriendRequestStatus>> getFriendRequestStatus({
    required String viewerUid,
    required String profileUid,
  });

  Future<Either<Failure, void>> sendFriendRequest({
    required String fromUid,
    required String toUid,
  });

  Future<Either<Failure, void>> cancelFriendRequest({
    required String uid,
    required String targetUid,
  });

  Future<Either<Failure, void>> acceptFriendRequest({
    required String uid,
    required String requesterUid,
  });

  Future<Either<Failure, void>> rejectFriendRequest({
    required String uid,
    required String requesterUid,
  });

  Future<Either<Failure, void>> unfriend({
    required String uid,
    required String targetUid,
  });

  Future<Either<Failure, void>> blockUser({
    required String uid,
    required String targetUid,
  });

  Future<Either<Failure, void>> unblockUser({
    required String uid,
    required String targetUid,
  });

  Future<Either<Failure, int>> getMutualFriendsCount({
    required String uid,
    required String otherUid,
  });

  Future<Either<Failure, List<String>>> getBlockedUsers(String uid);
}
