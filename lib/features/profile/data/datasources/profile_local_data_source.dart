import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/profile_model.dart';

abstract class ProfileLocalDataSource {
  Future<ProfileModel?> getCachedProfile(String uid);

  Future<void> cacheProfile(ProfileModel profile);

  Future<DateTime?> getLastSyncedAt(String uid);

  Future<void> setLastSyncedAt(String uid, DateTime time);

  Future<void> clearAll();
}

class ProfileLocalDataSourceImpl implements ProfileLocalDataSource {
  static const String _profileBoxName = 'profile_cache';
  static const String _syncMetaBoxName = 'profile_sync_meta';

  static ProfileModel? getCachedSync(String uid) {
    if (!Hive.isBoxOpen(_profileBoxName)) return null;
    final raw = Hive.box<Map>(_profileBoxName).get(uid);
    if (raw == null) return null;
    try {
      return ProfileModel.fromCacheJson(uid, Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Future<Box<Map>> _profileBox() async {
    if (Hive.isBoxOpen(_profileBoxName)) return Hive.box<Map>(_profileBoxName);
    return Hive.openBox<Map>(_profileBoxName);
  }

  Future<Box> _syncMetaBox() async {
    if (Hive.isBoxOpen(_syncMetaBoxName)) return Hive.box(_syncMetaBoxName);
    return Hive.openBox(_syncMetaBoxName);
  }

  @override
  Future<ProfileModel?> getCachedProfile(String uid) async {
    try {
      final box = await _profileBox();
      final raw = box.get(uid);
      if (raw == null) return null;
      return ProfileModel.fromCacheJson(uid, Map<String, dynamic>.from(raw));
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> cacheProfile(ProfileModel profile) async {
    try {
      final box = await _profileBox();
      await box.put(profile.uid, profile.toCacheJson());
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<DateTime?> getLastSyncedAt(String uid) async {
    try {
      final box = await _syncMetaBox();
      final millis = box.get(uid) as int?;
      return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setLastSyncedAt(String uid, DateTime time) async {
    try {
      final box = await _syncMetaBox();
      final existingMillis = box.get(uid) as int?;
      final newMillis = time.millisecondsSinceEpoch;
      if (existingMillis == null || newMillis > existingMillis) {
        await box.put(uid, newMillis);
      }
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      final profileBox = await _profileBox();
      await profileBox.clear();
      final syncBox = await _syncMetaBox();
      await syncBox.clear();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
