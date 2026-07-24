import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../repositories/user_search_repository.dart';

class SearchUsersUseCase {
  final UserSearchRepository repository;
  const SearchUsersUseCase(this.repository);

  Future<Either<Failure, List<ProfileEntity>>> call({
    required String query,
    required String viewerUid,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const Right(<ProfileEntity>[]);

    final result = await repository.fetchSearchCandidates(excludeUid: viewerUid);
    return result.map((candidates) => _rank(candidates, trimmed.toLowerCase()));
  }

  List<ProfileEntity> _rank(List<ProfileEntity> candidates, String normalizedQuery) {
    final scored = <_ScoredProfile>[];
    for (final profile in candidates) {
      final score = _scoreOf(profile, normalizedQuery);
      if (score != null) scored.add(_ScoredProfile(profile, score));
    }
    scored.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      return a.profile.username.compareTo(b.profile.username);
    });
    return scored.map((s) => s.profile).toList();
  }

  int? _scoreOf(ProfileEntity profile, String normalizedQuery) {
    final username = profile.username.toLowerCase();
    final displayName = profile.displayName.toLowerCase();

    if (username == normalizedQuery) return 0;
    if (displayName == normalizedQuery) return 1;
    if (username.startsWith(normalizedQuery) || displayName.startsWith(normalizedQuery)) return 2;
    if (username.contains(normalizedQuery) || displayName.contains(normalizedQuery)) return 3;
    if (_isSubsequence(normalizedQuery, username) || _isSubsequence(normalizedQuery, displayName)) return 4;
    return null;
  }

  bool _isSubsequence(String query, String source) {
    if (query.isEmpty || source.isEmpty) return false;
    int qi = 0;
    for (int i = 0; i < source.length && qi < query.length; i++) {
      if (source[i] == query[qi]) qi++;
    }
    return qi == query.length;
  }
}

class _ScoredProfile {
  final ProfileEntity profile;
  final int score;
  const _ScoredProfile(this.profile, this.score);
}
