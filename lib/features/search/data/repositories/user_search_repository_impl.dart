import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/repositories/friend_repository.dart';
import '../../domain/repositories/user_search_repository.dart';

const int kUserSearchCandidateLimit = 200;
const Duration kUserSearchQueryTimeout = Duration(seconds: 15);

class UserSearchRepositoryImpl implements UserSearchRepository {
  final FirebaseFirestore firestore;
  final FriendRepository friendRepository;
  const UserSearchRepositoryImpl({required this.firestore, required this.friendRepository});

  @override
  Future<Either<Failure, List<ProfileEntity>>> fetchSearchCandidates({
    required String excludeUid,
  }) async {
    try {
      final blockedResult = await friendRepository.getBlockedUsers(excludeUid);
      final blockedIds = blockedResult.fold((_) => const <String>[], (ids) => ids).toSet();

      final snapshot = await firestore
          .collection('users')
          .limit(kUserSearchCandidateLimit)
          .get()
          .timeout(kUserSearchQueryTimeout);
      final candidates = snapshot.docs
          .where((doc) => doc.id != excludeUid && !blockedIds.contains(doc.id))
          .map((doc) => ProfileModel.fromJson(doc.id, doc.data()))
          .toList();
      return Right(candidates);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }
}
