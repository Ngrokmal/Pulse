import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/offline_queue.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/entities/profile_visibility.dart';
import '../../domain/repositories/profile_repository.dart';
import '../models/profile_model.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  final FirebaseFirestore firestore;
  const ProfileRepositoryImpl({required this.firestore});

  DocumentReference<Map<String, dynamic>> _userRef(String uid) => firestore.collection('users').doc(uid);

  @override
  Stream<ProfileEntity> streamProfile(String uid) {
    final controller = StreamController<ProfileEntity>();

    // Root cause (offline friend still shown as Online): cloud_firestore
    // has offline persistence ON by default on mobile, so `.snapshots()`
    // can emit an event sourced purely from the *Firestore SDK's own*
    // on-device cache (`metadata.isFromCache == true`) — separate from and
    // invisible to our app-level FriendProfileCacheService. That
    // SDK-cached snapshot can carry a stale isOnline/lastSeen from before
    // the real server-confirmed value arrives, and the app-level cache
    // fix couldn't see this because it only ever received the value
    // *after* this stream had already emitted it. Fix: only forward
    // server-confirmed snapshots — our own disk cache already covers the
    // "instant first paint" need, so skipping the SDK's cache-sourced
    // replay here costs nothing and removes the stale-presence source.
    final subscription = _userRef(uid).snapshots().listen((snapshot) {
      if (snapshot.metadata.isFromCache) return;
      final data = snapshot.data();
      if (data == null) {
        if (!controller.isClosed) {
          controller.addError(StateError('Profile not found: $uid'));
        }
        return;
      }
      if (!controller.isClosed) {
        controller.add(ProfileModel.fromJson(uid, data));
      }
    }, onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    });

    controller.onCancel = () async {
      await subscription.cancel();
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> ensureProfileExists({
    required String uid,
    required String username,
    required String displayName,
    String? email,
  }) async {
    final ref = _userRef(uid);
    final snapshot = await ref.get();
    if (snapshot.exists) return;

    final model = ProfileModel(uid: uid, username: username, displayName: displayName, email: email);
    final json = model.toCreateJson();
    if (email != null) json['email'] = email;
    await ref.set(json, SetOptions(merge: true));
  }

  @override
  Future<void> updateProfile({required String uid, required Map<String, dynamic> updates}) async {
    if (updates.isEmpty) return;
    final sanitized = Map<String, dynamic>.from(updates)
      ..remove('verificationStatus')
      ..remove('uid')
      ..remove('friendsCount')
      ..remove('groupsCount');

    if (sanitized.containsKey('birthday') && sanitized['birthday'] is DateTime) {
      sanitized['birthday'] = Timestamp.fromDate(sanitized['birthday'] as DateTime);
    }

    return OfflineQueueManager.instance.addToQueue(() async {
      await _userRef(uid).set(sanitized, SetOptions(merge: true));
    });
  }

  @override
  Future<void> updateAvatarPhoto({required String uid, required String url, required String publicId}) {
    return OfflineQueueManager.instance.addToQueue(() async {
      await _userRef(uid).set({'avatarUrl': url, 'avatarPublicId': publicId}, SetOptions(merge: true));
    });
  }

  @override
  Future<void> removeAvatarPhoto(String uid) {
    return OfflineQueueManager.instance.addToQueue(() async {
      await _userRef(uid).set({'avatarUrl': FieldValue.delete(), 'avatarPublicId': FieldValue.delete()}, SetOptions(merge: true));
    });
  }

  @override
  Future<void> updateCoverPhoto({required String uid, required String url, required String publicId}) {
    return OfflineQueueManager.instance.addToQueue(() async {
      await _userRef(uid).set({'coverUrl': url, 'coverPublicId': publicId}, SetOptions(merge: true));
    });
  }

  @override
  Future<void> removeCoverPhoto(String uid) {
    return OfflineQueueManager.instance.addToQueue(() async {
      await _userRef(uid).set({'coverUrl': FieldValue.delete(), 'coverPublicId': FieldValue.delete()}, SetOptions(merge: true));
    });
  }

  @override
  Future<void> setOnlineStatus({required String uid, required bool isOnline}) async {
    await _userRef(uid).set({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<Either<Failure, int>> getFriendsCount(String uid) async {
    try {
      final snapshot = await _userRef(uid).collection('friends').get();
      return Right(snapshot.docs.length);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> getMutualGroupsCount({required String uid, required String otherUid}) async {
    try {
      final ownGroups = await firestore.collection('chats').where('memberUids', arrayContains: uid).get();
      final ownGroupIds = ownGroups.docs.where((d) => d.data().containsKey('adminIds')).map((d) => d.id).toSet();

      if (ownGroupIds.isEmpty) return const Right(0);

      final otherGroups = await firestore.collection('chats').where('memberUids', arrayContains: otherUid).get();
      final otherGroupIds = otherGroups.docs.where((d) => d.data().containsKey('adminIds')).map((d) => d.id).toSet();

      return Right(ownGroupIds.intersection(otherGroupIds).length);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ProfileVisibility>> getRelationshipStatus({
    required String viewerUid,
    required String profileUid,
  }) async {
    try {
      final blockedByProfile = await _userRef(profileUid).collection('blocked').doc(viewerUid).get();
      if (blockedByProfile.exists) return const Right(ProfileVisibility.blocked);

      final blockedByViewer = await _userRef(viewerUid).collection('blocked').doc(profileUid).get();
      if (blockedByViewer.exists) return const Right(ProfileVisibility.blocked);

      final friendship = await _userRef(viewerUid).collection('friends').doc(profileUid).get();
      if (friendship.exists) return const Right(ProfileVisibility.friend);

      return const Right(ProfileVisibility.nonFriend);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }
}
