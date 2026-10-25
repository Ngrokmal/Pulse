import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';

const Duration kAdminQueryTimeout = Duration(seconds: 15);
const String _kUserRowColumns =
    'id, username, display_name, full_name, bio, location, gender, birthday, phone, email, website, '
    'avatar_url, avatar_public_id, cover_url, cover_public_id, friends_count, groups_count, '
    'verification_status, is_banned, is_disabled, ban_type, ban_expires_at, banned_at, disabled_at, '
    'created_at, updated_at';

abstract class AdminRemoteDataSource {
  Future<int> countUsers();
  Future<int> countChats({required bool isGroup});
  Future<int> countAcceptedFriendships();

  Future<Map<String, dynamic>?> fetchUserById(String supabaseUid);
  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query, {int limit = 20});
  Future<void> updateUserModerationFields(String supabaseUid, Map<String, dynamic> updates);

  Future<Map<String, dynamic>> insertBanHistory(Map<String, dynamic> row);
  Future<void> liftActiveBans(String supabaseTargetId);
  Future<List<Map<String, dynamic>>> fetchBanHistory(String supabaseTargetId);

  Future<Map<String, dynamic>> insertReport(Map<String, dynamic> row);
  Future<List<Map<String, dynamic>>> fetchAllReports();
  Future<List<Map<String, dynamic>>> fetchReportsUpdatedSince(DateTime since);
  Future<void> updateReportStatus(String reportId, String statusColumn);

  Future<Map<String, dynamic>> insertWarning(Map<String, dynamic> row);
  Future<List<Map<String, dynamic>>> fetchWarnings(String supabaseUserId);

  Future<Map<String, dynamic>> insertActionLog(Map<String, dynamic> row);
  Future<List<Map<String, dynamic>>> fetchAllActionLog();
  Future<List<Map<String, dynamic>>> fetchActionLogCreatedSince(DateTime since);

  RealtimeChannel watchUsers(void Function(Map<String, dynamic> row) onChange);

  RealtimeChannel watchReports(void Function(Map<String, dynamic> row) onChange);

  Stream<void> watchAdminActivity();
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  final SupabaseClient _client;

  AdminRemoteDataSourceImpl({required SupabaseClient client}) : _client = client;

  Future<T> _run<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(kAdminQueryTimeout);
    } on AuthException catch (e) {
      throw ServerException(message: e.message);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message);
    } on SocketException catch (e) {
      throw NetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw NetworkException(message: e.message ?? 'Connection Timeout');
    } on PlatformException catch (e) {
      throw ServerException(message: e.message ?? 'Platform Error');
    } catch (e) {
      throw UnknownException(message: e.toString());
    }
  }

  @override
  Future<int> countUsers() => _run(() async {
        final res = await _client.from('users').select('id').count(CountOption.exact);
        return res.count;
      });

  @override
  Future<int> countChats({required bool isGroup}) => _run(() async {
        final res = await _client
            .from('chats')
            .select('id')
            .eq('type', isGroup ? 'group' : 'direct')
            .count(CountOption.exact);
        return res.count;
      });

  @override
  Future<int> countAcceptedFriendships() => _run(() async {
        final res =
            await _client.from('friendships').select('id').eq('status', 'accepted').count(CountOption.exact);
        return res.count;
      });

  @override
  Future<Map<String, dynamic>?> fetchUserById(String supabaseUid) => _run(() async {
        return await _client.from('users').select(_kUserRowColumns).eq('id', supabaseUid).maybeSingle();
      });

  @override
  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query, {int limit = 20}) => _run(() async {
        final rows = await _client
            .from('users')
            .select(_kUserRowColumns)
            .ilike('username', '%$query%')
            .order('username')
            .limit(limit);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<void> updateUserModerationFields(String supabaseUid, Map<String, dynamic> updates) => _run(() async {
        await _client.from('users').update(updates).eq('id', supabaseUid);
      });

  @override
  Future<Map<String, dynamic>> insertBanHistory(Map<String, dynamic> row) => _run(() async {
        return await _client.from('user_ban_history').insert(row).select().single();
      });

  @override
  Future<void> liftActiveBans(String supabaseTargetId) => _run(() async {
        await _client
            .from('user_ban_history')
            .update({'status': 'lifted'})
            .eq('target_id', supabaseTargetId)
            .eq('status', 'active');
      });

  @override
  Future<List<Map<String, dynamic>>> fetchBanHistory(String supabaseTargetId) => _run(() async {
        final rows = await _client
            .from('user_ban_history')
            .select()
            .eq('target_id', supabaseTargetId)
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<Map<String, dynamic>> insertReport(Map<String, dynamic> row) => _run(() async {
        return await _client.from('reports').insert(row).select().single();
      });

  @override
  Future<List<Map<String, dynamic>>> fetchAllReports() => _run(() async {
        final rows = await _client.from('reports').select().order('updated_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<List<Map<String, dynamic>>> fetchReportsUpdatedSince(DateTime since) => _run(() async {
        final rows = await _client
            .from('reports')
            .select()
            .gt('updated_at', since.toUtc().toIso8601String())
            .order('updated_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<void> updateReportStatus(String reportId, String statusColumn) => _run(() async {
        await _client.from('reports').update({'status': statusColumn}).eq('id', reportId);
      });

  @override
  Future<Map<String, dynamic>> insertWarning(Map<String, dynamic> row) => _run(() async {
        return await _client.from('user_warnings').insert(row).select().single();
      });

  @override
  Future<List<Map<String, dynamic>>> fetchWarnings(String supabaseUserId) => _run(() async {
        final rows = await _client
            .from('user_warnings')
            .select()
            .eq('user_id', supabaseUserId)
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<Map<String, dynamic>> insertActionLog(Map<String, dynamic> row) => _run(() async {
        return await _client.from('admin_action_logs').insert(row).select().single();
      });

  @override
  Future<List<Map<String, dynamic>>> fetchAllActionLog() => _run(() async {
        final rows = await _client.from('admin_action_logs').select().order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  Future<List<Map<String, dynamic>>> fetchActionLogCreatedSince(DateTime since) => _run(() async {
        final rows = await _client
            .from('admin_action_logs')
            .select()
            .gt('created_at', since.toUtc().toIso8601String())
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(rows);
      });

  @override
  RealtimeChannel watchUsers(void Function(Map<String, dynamic> row) onChange) {
    return _client.channel('admin_users_watch').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'users',
      callback: (payload) {
        final row = payload.newRecord;
        if (row.isNotEmpty) onChange(row);
      },
    ).subscribe();
  }

  @override
  RealtimeChannel watchReports(void Function(Map<String, dynamic> row) onChange) {
    return _client.channel('admin_reports_watch').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'reports',
      callback: (payload) {
        final row = payload.newRecord;
        if (row.isNotEmpty) onChange(row);
      },
    ).subscribe();
  }

  StreamController<void>? _activityController;
  RealtimeChannel? _activityChannel;

  void _pingActivity([dynamic _]) {
    final controller = _activityController;
    if (controller != null && !controller.isClosed) controller.add(null);
  }

  @override
  Stream<void> watchAdminActivity() {
    final existing = _activityController;
    if (existing != null && !existing.isClosed) return existing.stream;

    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        _activityChannel = _client
            .channel('admin_activity')
            .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'users', callback: _pingActivity)
            .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'reports', callback: _pingActivity)
            .subscribe();
      },
      onCancel: () async {
        final c = _activityChannel;
        _activityChannel = null;
        if (c != null) await _client.removeChannel(c);
      },
    );
    _activityController = controller;
    return controller.stream;
  }
}
