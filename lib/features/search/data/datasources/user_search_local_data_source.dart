import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/search_candidate_model.dart';

abstract class UserSearchLocalDataSource {
  Future<List<SearchCandidateModel>> getCachedCandidates();

  Future<void> upsertCandidates(List<SearchCandidateModel> candidates);
}

class UserSearchLocalDataSourceImpl implements UserSearchLocalDataSource {
  static const String _candidatesBoxName = 'search_candidates_cache';

  Future<Box<Map>> _candidatesBox() async {
    if (Hive.isBoxOpen(_candidatesBoxName)) return Hive.box<Map>(_candidatesBoxName);
    return Hive.openBox<Map>(_candidatesBoxName);
  }

  @override
  Future<List<SearchCandidateModel>> getCachedCandidates() async {
    try {
      final box = await _candidatesBox();
      return box.values
          .map((raw) => SearchCandidateModel.fromCacheJson(Map<String, dynamic>.from(raw)))
          .toList();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> upsertCandidates(List<SearchCandidateModel> candidates) async {
    if (candidates.isEmpty) return;
    try {
      final box = await _candidatesBox();
      for (final candidate in candidates) {
        await box.put(candidate.uid, candidate.toCacheJson());
      }
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
