import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/profile_entity.dart';
import '../entities/profile_visibility.dart';

abstract class ProfileRepository {
  Stream<ProfileEntity> streamProfile(String uid);

  Future<void> ensureProfileExists({
    required String uid,
    required String username,
    required String displayName,
    String? email,
  });

  Future<void> updateProfile({
    required String uid,
    required Map<String, dynamic> updates,
  });

  Future<void> updateAvatarPhoto({
    required String uid,
    required String url,
    required String publicId,
  });

  Future<void> removeAvatarPhoto(String uid);

  Future<void> updateCoverPhoto({
    required String uid,
    required String url,
    required String publicId,
  });

  Future<void> removeCoverPhoto(String uid);

  Future<void> setOnlineStatus({required String uid, required bool isOnline});

  Future<Either<Failure, int>> getFriendsCount(String uid);

  Future<Either<Failure, int>> getMutualGroupsCount({
    required String uid,
    required String otherUid,
  });

  Future<Either<Failure, ProfileVisibility>> getRelationshipStatus({
    required String viewerUid,
    required String profileUid,
  });
}
