import '../../../../core/services/local_db_service.dart';
import '../../../../core/sync/sync_engine.dart';

abstract class FriendLocalDataSource {
  Future<List<String>> getCachedFriendIds(String uid);

  Future<void> upsertFriendship({
    required String uid,
    required String counterpartUid,
    required bool isAccepted,
  });

  Future<DateTime?> getFriendsSyncedAt(String uid);

  Future<void> setFriendsSyncedAt(String uid, DateTime time);
}

class FriendLocalDataSourceImpl implements FriendLocalDataSource {
  @override
  Future<List<String>> getCachedFriendIds(String uid) async {
    final box = await LocalDbService.friendsBox(uid);
    return box.values.toList();
  }

  @override
  Future<void> upsertFriendship({
    required String uid,
    required String counterpartUid,
    required bool isAccepted,
  }) async {
    final box = await LocalDbService.friendsBox(uid);
    if (isAccepted) {
      await box.put(counterpartUid, counterpartUid);
    } else {
      await box.delete(counterpartUid);
    }
  }

  @override
  Future<DateTime?> getFriendsSyncedAt(String uid) {
    return SyncEngine.instance.getCursor('friendsSyncedAt_$uid');
  }

  @override
  Future<void> setFriendsSyncedAt(String uid, DateTime time) {
    return SyncEngine.instance.setCursor('friendsSyncedAt_$uid', time);
  }
}
