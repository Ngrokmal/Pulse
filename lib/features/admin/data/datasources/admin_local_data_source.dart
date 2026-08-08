import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/admin_dashboard_stats.dart';

abstract class AdminLocalDataSource {
  Future<Map<String, dynamic>?> getCachedUserRow(String supabaseUid);
  Future<void> upsertUserRow(String supabaseUid, Map<String, dynamic> row);
  Future<List<Map<String, dynamic>>> searchCachedUsersByUsername(String query, {int limit = 20});

  Future<AdminDashboardStats?> getCachedDashboardStats();
  Future<void> setCachedDashboardStats(AdminDashboardStats stats);

  Future<List<Map<String, dynamic>>> getCachedReports();
  Future<void> upsertReports(List<Map<String, dynamic>> rows);
  Future<void> upsertReportRow(Map<String, dynamic> row);
  Future<DateTime?> getReportsLastSyncedAt();
  Future<void> setReportsLastSyncedAt(DateTime time);

  Future<List<Map<String, dynamic>>> getCachedBanHistory(String supabaseTargetId);
  Future<void> setCachedBanHistory(String supabaseTargetId, List<Map<String, dynamic>> rows);

  Future<List<Map<String, dynamic>>> getCachedWarnings(String supabaseUserId);
  Future<void> setCachedWarnings(String supabaseUserId, List<Map<String, dynamic>> rows);

  Future<List<Map<String, dynamic>>> getCachedActionLog();
  Future<void> setCachedActionLog(List<Map<String, dynamic>> rows);
  Future<DateTime?> getActionLogLastSyncedAt();
  Future<void> setActionLogLastSyncedAt(DateTime time);
}

class AdminLocalDataSourceImpl implements AdminLocalDataSource {
  static const String _usersBoxName = 'admin_users_cache';
  static const String _reportsBoxName = 'admin_reports_cache';
  static const String _banHistoryBoxName = 'admin_ban_history_cache';
  static const String _warningsBoxName = 'admin_warnings_cache';
  static const String _actionLogBoxName = 'admin_action_log_cache';
  static const String _dashboardBoxName = 'admin_dashboard_cache';
  static const String _syncMetaBoxName = 'admin_sync_meta';

  static const String _dashboardKey = 'stats';
  static const String _actionLogKey = 'entries';
  static const String _reportsLastSyncedKey = 'reportsLastSyncedAt';
  static const String _actionLogLastSyncedKey = 'actionLogLastSyncedAt';

  Future<Box<Map>> _box(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<Map>(name);
    return Hive.openBox<Map>(name);
  }

  Future<Box> _plainBox(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name);
  }

  @override
  Future<Map<String, dynamic>?> getCachedUserRow(String supabaseUid) async {
    try {
      final box = await _box(_usersBoxName);
      final raw = box.get(supabaseUid);
      return raw != null ? Map<String, dynamic>.from(raw) : null;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> upsertUserRow(String supabaseUid, Map<String, dynamic> row) async {
    try {
      final box = await _box(_usersBoxName);
      await box.put(supabaseUid, row);
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchCachedUsersByUsername(String query, {int limit = 20}) async {
    try {
      final box = await _box(_usersBoxName);
      final lower = query.toLowerCase();
      final matches = box.values
          .map((raw) => Map<String, dynamic>.from(raw))
          .where((row) => (row['username'] as String? ?? '').toLowerCase().contains(lower))
          .toList();
      matches.sort((a, b) => (a['username'] as String? ?? '').compareTo(b['username'] as String? ?? ''));
      return matches.take(limit).toList();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<AdminDashboardStats?> getCachedDashboardStats() async {
    try {
      final box = await _box(_dashboardBoxName);
      final raw = box.get(_dashboardKey);
      if (raw == null) return null;
      return AdminDashboardStats(
        totalUsers: raw['totalUsers'] as int? ?? 0,
        totalFriends: raw['totalFriends'] as int? ?? 0,
        totalChats: raw['totalChats'] as int? ?? 0,
        totalGroups: raw['totalGroups'] as int? ?? 0,
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setCachedDashboardStats(AdminDashboardStats stats) async {
    try {
      final box = await _box(_dashboardBoxName);
      await box.put(_dashboardKey, {
        'totalUsers': stats.totalUsers,
        'totalFriends': stats.totalFriends,
        'totalChats': stats.totalChats,
        'totalGroups': stats.totalGroups,
      });
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCachedReports() async {
    try {
      final box = await _box(_reportsBoxName);
      return box.values.map((raw) => Map<String, dynamic>.from(raw)).toList();
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> upsertReports(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      final box = await _box(_reportsBoxName);
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id != null) await box.put(id, row);
      }
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> upsertReportRow(Map<String, dynamic> row) => upsertReports([row]);

  @override
  Future<DateTime?> getReportsLastSyncedAt() async {
    try {
      final box = await _plainBox(_syncMetaBoxName);
      final millis = box.get(_reportsLastSyncedKey) as int?;
      return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setReportsLastSyncedAt(DateTime time) async {
    try {
      final box = await _plainBox(_syncMetaBoxName);
      final existing = box.get(_reportsLastSyncedKey) as int?;
      final newMillis = time.millisecondsSinceEpoch;
      if (existing == null || newMillis > existing) await box.put(_reportsLastSyncedKey, newMillis);
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCachedBanHistory(String supabaseTargetId) async {
    try {
      final box = await _box(_banHistoryBoxName);
      final raw = box.get(supabaseTargetId);
      if (raw == null) return const [];
      return List<Map<String, dynamic>>.from(
        (raw as Map)['rows'].map((r) => Map<String, dynamic>.from(r)),
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setCachedBanHistory(String supabaseTargetId, List<Map<String, dynamic>> rows) async {
    try {
      final box = await _box(_banHistoryBoxName);
      await box.put(supabaseTargetId, {'rows': rows});
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCachedWarnings(String supabaseUserId) async {
    try {
      final box = await _box(_warningsBoxName);
      final raw = box.get(supabaseUserId);
      if (raw == null) return const [];
      return List<Map<String, dynamic>>.from(
        (raw as Map)['rows'].map((r) => Map<String, dynamic>.from(r)),
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setCachedWarnings(String supabaseUserId, List<Map<String, dynamic>> rows) async {
    try {
      final box = await _box(_warningsBoxName);
      await box.put(supabaseUserId, {'rows': rows});
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getCachedActionLog() async {
    try {
      final box = await _box(_actionLogBoxName);
      final raw = box.get(_actionLogKey);
      if (raw == null) return const [];
      return List<Map<String, dynamic>>.from(
        (raw as Map)['rows'].map((r) => Map<String, dynamic>.from(r)),
      );
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setCachedActionLog(List<Map<String, dynamic>> rows) async {
    try {
      final box = await _box(_actionLogBoxName);
      await box.put(_actionLogKey, {'rows': rows});
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<DateTime?> getActionLogLastSyncedAt() async {
    try {
      final box = await _plainBox(_syncMetaBoxName);
      final millis = box.get(_actionLogLastSyncedKey) as int?;
      return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }

  @override
  Future<void> setActionLogLastSyncedAt(DateTime time) async {
    try {
      final box = await _plainBox(_syncMetaBoxName);
      final existing = box.get(_actionLogLastSyncedKey) as int?;
      final newMillis = time.millisecondsSinceEpoch;
      if (existing == null || newMillis > existing) await box.put(_actionLogLastSyncedKey, newMillis);
    } catch (e) {
      throw CacheException(message: e.toString());
    }
  }
}
