import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/friend_request_status.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/repositories/friend_repository.dart';

class FriendRepositoryImpl implements FriendRepository {
  final FirebaseFirestore firestore;
  const FriendRepositoryImpl({required this.firestore});

  DocumentReference<Map<String, dynamic>> _userRef(String uid) => firestore.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _requestRef(String ownerUid, String otherUid) =>
      _userRef(ownerUid).collection('friendRequests').doc(otherUid);

  DocumentReference<Map<String, dynamic>> _friendRef(String ownerUid, String otherUid) =>
      _userRef(ownerUid).collection('friends').doc(otherUid);

  DocumentReference<Map<String, dynamic>> _blockedRef(String ownerUid, String otherUid) =>
      _userRef(ownerUid).collection('blocked').doc(otherUid);

  @override
  Future<Either<Failure, FriendRequestStatus>> getFriendRequestStatus({
    required String viewerUid,
    required String profileUid,
  }) async {
    try {
      final friendship = await _friendRef(viewerUid, profileUid).get();
      if (friendship.exists) return const Right(FriendRequestStatus.friends);

      final request = await _requestRef(viewerUid, profileUid).get();
      if (request.exists) {
        final fromUid = request.data()?['fromUid'] as String?;
        return Right(fromUid == viewerUid ? FriendRequestStatus.requestSent : FriendRequestStatus.requestReceived);
      }

      return const Right(FriendRequestStatus.notFriends);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> sendFriendRequest({required String fromUid, required String toUid}) async {
    if (fromUid == toUid) return const Right(null);
    try {
      final blockedByTarget = await _blockedRef(toUid, fromUid).get();
      if (blockedByTarget.exists) return const Left(FirebaseFailure('Unable to send friend request.'));

      final blockedByMe = await _blockedRef(fromUid, toUid).get();
      if (blockedByMe.exists) return const Left(FirebaseFailure('Unable to send friend request.'));

      final targetSnapshot = await _userRef(toUid).get();
      final privacy = friendRequestPrivacyFromString(targetSnapshot.data()?['friendRequestPrivacy'] as String?);
      if (privacy == FriendRequestPrivacy.nobody) {
        return const Left(FirebaseFailure('This user is not accepting friend requests.'));
      }
      if (privacy == FriendRequestPrivacy.friendsOfFriends) {
        final mutualResult = await getMutualFriendsCount(uid: fromUid, otherUid: toUid);
        final mutualCount = mutualResult.fold((_) => 0, (count) => count);
        if (mutualCount <= 0) {
          return const Left(FirebaseFailure('This user only accepts requests from friends of friends.'));
        }
      }

      final alreadyFriends = await _friendRef(fromUid, toUid).get();
      if (alreadyFriends.exists) return const Right(null);

      final existingRequest = await _requestRef(fromUid, toUid).get();
      if (existingRequest.exists) return const Right(null);

      final batch = firestore.batch();
      final payload = {'fromUid': fromUid, 'toUid': toUid, 'createdAt': FieldValue.serverTimestamp()};
      batch.set(_requestRef(fromUid, toUid), payload);
      batch.set(_requestRef(toUid, fromUid), payload);
      await batch.commit();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> cancelFriendRequest({required String uid, required String targetUid}) async {
    try {
      final batch = firestore.batch();
      batch.delete(_requestRef(uid, targetUid));
      batch.delete(_requestRef(targetUid, uid));
      await batch.commit();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> acceptFriendRequest({required String uid, required String requesterUid}) async {
    try {
      final batch = firestore.batch();
      batch.delete(_requestRef(uid, requesterUid));
      batch.delete(_requestRef(requesterUid, uid));

      final friendPayload = {'createdAt': FieldValue.serverTimestamp()};
      batch.set(_friendRef(uid, requesterUid), friendPayload);
      batch.set(_friendRef(requesterUid, uid), friendPayload);

      batch.update(_userRef(uid), {'friendsCount': FieldValue.increment(1)});
      batch.update(_userRef(requesterUid), {'friendsCount': FieldValue.increment(1)});

      await batch.commit();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> rejectFriendRequest({required String uid, required String requesterUid}) async {
    try {
      final batch = firestore.batch();
      batch.delete(_requestRef(uid, requesterUid));
      batch.delete(_requestRef(requesterUid, uid));
      await batch.commit();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> unfriend({required String uid, required String targetUid}) async {
    try {
      final friendship = await _friendRef(uid, targetUid).get();
      if (!friendship.exists) return const Right(null);

      final batch = firestore.batch();
      batch.delete(_friendRef(uid, targetUid));
      batch.delete(_friendRef(targetUid, uid));
      batch.update(_userRef(uid), {'friendsCount': FieldValue.increment(-1)});
      batch.update(_userRef(targetUid), {'friendsCount': FieldValue.increment(-1)});
      await batch.commit();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> blockUser({required String uid, required String targetUid}) async {
    if (uid == targetUid) return const Right(null);
    try {
      final friendship = await _friendRef(uid, targetUid).get();
      final request = await _requestRef(uid, targetUid).get();

      final batch = firestore.batch();
      batch.set(_blockedRef(uid, targetUid), {'createdAt': FieldValue.serverTimestamp()});

      if (friendship.exists) {
        batch.delete(_friendRef(uid, targetUid));
        batch.delete(_friendRef(targetUid, uid));
        batch.update(_userRef(uid), {'friendsCount': FieldValue.increment(-1)});
        batch.update(_userRef(targetUid), {'friendsCount': FieldValue.increment(-1)});
      }

      if (request.exists) {
        batch.delete(_requestRef(uid, targetUid));
        batch.delete(_requestRef(targetUid, uid));
      }

      await batch.commit();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> unblockUser({required String uid, required String targetUid}) async {
    try {
      await _blockedRef(uid, targetUid).delete();
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> getMutualFriendsCount({required String uid, required String otherUid}) async {
    try {
      final ownFriends = await _userRef(uid).collection('friends').get();
      if (ownFriends.docs.isEmpty) return const Right(0);
      final ownFriendIds = ownFriends.docs.map((d) => d.id).toSet();

      final otherFriends = await _userRef(otherUid).collection('friends').get();
      final otherFriendIds = otherFriends.docs.map((d) => d.id).toSet();

      return Right(ownFriendIds.intersection(otherFriendIds).length);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getBlockedUsers(String uid) async {
    try {
      final snapshot = await _userRef(uid).collection('blocked').get();
      return Right(snapshot.docs.map((d) => d.id).toList());
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }
}
