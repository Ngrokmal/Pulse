import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/repositories/friend_repository.dart';
import '../../domain/repositories/user_search_repository.dart';
import '../datasources/user_search_local_data_source.dart';
import '../datasources/user_search_remote_data_source.dart';
import '../models/search_candidate_model.dart';

class UserSearchRepositoryImpl implements UserSearchRepository {
  final UserSearchRemoteDataSource remoteDataSource;
  final UserSearchLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final FriendRepository friendRepository;

  const UserSearchRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.supabase,
    required this.friendRepository,
  });

  String? _currentSupabaseUid() => supabase.auth.currentUser?.id;

  @override
  Future<Either<Failure, List<ProfileEntity>>> searchUsers({
    required String query,
    required String excludeUid,
  }) async {
    final blockedFuture = friendRepository.getBlockedUsers(excludeUid);

    List<ProfileEntity> candidates;
    try {
      candidates = await _searchRemote(query: query, excludeUid: excludeUid);
    } catch (_) {
      try {
        candidates = await localDataSource.getCachedCandidates();
      } on CacheException catch (e) {
        return Left(FirebaseFailure(e.message));
      } catch (e) {
        return Left(FirebaseFailure(e.toString()));
      }
    }

    try {
      final blockedResult = await blockedFuture;
      final blockedIds = blockedResult.fold((_) => const <String>[], (ids) => ids).toSet();

      final filtered = candidates
          .where((c) => c.uid.isNotEmpty && c.uid != excludeUid && !blockedIds.contains(c.uid))
          .toList();

      return Right(filtered);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  Future<List<ProfileEntity>> _searchRemote({
    required String query,
    required String excludeUid,
  }) async {
    final excludeSupabaseUid = await UserIdBridge.resolve(
      excludeUid,
      currentSupabaseUserId: _currentSupabaseUid(),
    );

    final rows = await remoteDataSource.searchUsers(
      query: query,
      excludeSupabaseUid: excludeSupabaseUid,
    );

    final models = <SearchCandidateModel>[];
    for (final row in rows) {
      final supabaseId = row['id'] as String?;
      if (supabaseId == null) continue;
      final firebaseUid = await UserIdBridge.reverseResolve(supabaseId) ?? supabaseId;
      models.add(SearchCandidateModel.fromSupabaseRow(row, firebaseUid: firebaseUid));
    }

    if (models.isNotEmpty) {
      unawaited(localDataSource.upsertCandidates(models).catchError((_) {}));
    }

    return models;
  }
}
