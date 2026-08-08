import 'package:hive_flutter/hive_flutter.dart';

import '../services/local_db_service.dart';

class SyncEngine {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  Future<Box> _metaBox() => LocalDbService.syncMetaBox();

  Future<DateTime?> getCursor(String key) async {
    final box = await _metaBox();
    final millis = box.get(key) as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  Future<void> setCursor(String key, DateTime time) async {
    final box = await _metaBox();
    final existingMillis = box.get(key) as int?;
    final newMillis = time.millisecondsSinceEpoch;
    if (existingMillis == null || newMillis > existingMillis) {
      await box.put(key, newMillis);
    }
  }

  Future<DateTime> runDelta<T>({
    required Future<DateTime?> Function() getCursor,
    required Future<void> Function(DateTime time) setCursor,
    required Future<List<T>> Function(DateTime since) fetchChanges,
    required DateTime Function(T item) updatedAtOf,
    required Future<void> Function(T item) onUpsert,
    bool Function(T item)? isTombstone,
    Future<void> Function(T item)? onTombstone,
    DateTime? epoch,
  }) async {
    final cursor = await getCursor() ?? epoch ?? DateTime.fromMillisecondsSinceEpoch(0);
    final rows = await fetchChanges(cursor);
    if (rows.isEmpty) return cursor;

    DateTime latest = cursor;
    for (final item in rows) {
      final updatedAt = updatedAtOf(item);
      if (updatedAt.isAfter(latest)) latest = updatedAt;

      if (isTombstone != null && isTombstone(item)) {
        if (onTombstone != null) await onTombstone(item);
      } else {
        await onUpsert(item);
      }
    }
    await setCursor(latest);
    return latest;
  }
}
