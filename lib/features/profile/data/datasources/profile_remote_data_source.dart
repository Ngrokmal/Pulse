import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/profile_visibility.dart';

const Duration kProfileQueryTimeout = Duration(seconds: 15);

const String _kUserColumns = 'id, email, username, display_name, bio, location, gender, birthday, phone, '
    'website, avatar_url, avatar_public_id, cover_url, cover_public_id, friends_count, groups_count, '
    'verification_status, created_at, updated_at';

const String _kSettingsColumns = 'owner_id, notifications_enabled, profile_privacy, last_seen_visibility, '
    'online_status_visibility, friend_request_privacy, theme_mode, enter_to_send, read_receipts_enabled, '
    'typing_indicator_enabled, auto_download_images, auto_download_videos, auto_download_files, '
    'media_wifi_only, updated_at';

const String _kPresenceColumns = 'user_id, is_online, last_seen, updated_at';

abstract class ProfileRemoteDataSource {
  Future<Map<String, dynamic>?> fetchUserRow(String supabaseUid);
  Future<Map<String, dynamic>?> fetchSettingsRow(String supabaseUid);
  Future<Map<String, dynamic>?> fetchPresenceRow(String supabaseUid);

  Future<List<Map<String, dynamic>>> fetchUserRowsBatch(List<String> supabaseUids);

  Future<List<Map<String, dynamic>>> fetchPresenceRowsBatch(List<String> supabaseUids);

  Future<Map<String, dynamic>?> fetchUserRowUpdatedSince({
    required String supabaseUid,
    required DateTime since,
  });

  Future<void> ensureUserRowExists({
    required String supabaseUid,
    required String username,
    required String displayName,
    String? email,
  });

  Future<void> updateUserFields({required String supabaseUid, required Map<String, dynamic> columns});
  Future<void> updateSettingsFields({required String supabaseUid, required Map<String, dynamic> columns});

  Future<void> upsertPresence({
    required String supabaseUid,
    required bool isOnline,
    required DateTime lastSeen,
    required String deviceId,
  });

  Future<void> heartbeatPresence({required String deviceId});

  Future<int> fetchFriendsCount(String supabaseUid);

  Future<int> fetchMutualGroupsCount(String otherSupabaseUid);

  Future<ProfileVisibility> fetchRelationshipStatus(String otherSupabaseUid);
}

class ProfileRemoteDataSourceImpl implements ProfileRemoteDataSource {
  final SupabaseClient _client;

  ProfileRemoteDataSourceImpl({required SupabaseClient client}) : _client = client;

  T _rethrowMapped<T>(Object e) {
    if (e is AuthException) throw ServerException(message: e.message);
    if (e is PostgrestException) throw ServerException(message: e.message);
    if (e is SocketException) throw NetworkException(message: e.message);
    if (e is TimeoutException) throw NetworkException(message: e.message ?? 'Connection Timeout');
    if (e is PlatformException) throw ServerException(message: e.message ?? 'Platform Error');
    throw UnknownException(message: e.toString());
  }

  @override
  Future<Map<String, dynamic>?> fetchUserRow(String supabaseUid) async {
    try {
      final row = await _client
          .from('users')
          .select(_kUserColumns)
          .eq('id', supabaseUid)
          .maybeSingle()
          .timeout(kProfileQueryTimeout);
      return row;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchUserRowUpdatedSince({
    required String supabaseUid,
    required DateTime since,
  }) async {
    try {
      final rows = await _client
          .from('users')
          .select(_kUserColumns)
          .eq('id', supabaseUid)
          .gt('updated_at', since.toUtc().toIso8601String())
          .limit(1)
          .timeout(kProfileQueryTimeout);
      final list = List<Map<String, dynamic>>.from(rows);
      return list.isEmpty ? null : list.first;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchSettingsRow(String supabaseUid) async {
    try {
      final row = await _client
          .from('user_settings')
          .select(_kSettingsColumns)
          .eq('owner_id', supabaseUid)
          .maybeSingle()
          .timeout(kProfileQueryTimeout);
      return row;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchPresenceRow(String supabaseUid) async {
    try {
      final row = await _client
          .from('user_presence')
          .select(_kPresenceColumns)
          .eq('user_id', supabaseUid)
          .maybeSingle()
          .timeout(kProfileQueryTimeout);
      return row;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUserRowsBatch(List<String> supabaseUids) async {
    if (supabaseUids.isEmpty) return const [];
    try {
      final rows = await _client
          .from('users')
          .select(_kUserColumns)
          .inFilter('id', supabaseUids)
          .timeout(kProfileQueryTimeout);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPresenceRowsBatch(List<String> supabaseUids) async {
    if (supabaseUids.isEmpty) return const [];
    try {
      final rows = await _client
          .from('user_presence')
          .select(_kPresenceColumns)
          .inFilter('user_id', supabaseUids)
          .timeout(kProfileQueryTimeout);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<void> ensureUserRowExists({
    required String supabaseUid,
    required String username,
    required String displayName,
    String? email,
  }) async {
    try {
      final existing = await _client
          .from('users')
          .select('id')
          .eq('id', supabaseUid)
          .maybeSingle()
          .timeout(kProfileQueryTimeout);
      if (existing != null) return;

      if (email == null || email.isEmpty) return;

      await _client.from('users').insert({
        'id': supabaseUid,
        'username': username,
        'display_name': displayName,
        'email': email,
      }).timeout(kProfileQueryTimeout);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<void> updateUserFields({required String supabaseUid, required Map<String, dynamic> columns}) async {
    if (columns.isEmpty) return;
    try {
      await _client.from('users').update(columns).eq('id', supabaseUid).timeout(kProfileQueryTimeout);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<void> updateSettingsFields({required String supabaseUid, required Map<String, dynamic> columns}) async {
    if (columns.isEmpty) return;
    try {
      await _client.from('user_settings').update(columns).eq('owner_id', supabaseUid).timeout(kProfileQueryTimeout);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<void> upsertPresence({
    required String supabaseUid,
    required bool isOnline,
    required DateTime lastSeen,
    required String deviceId,
  }) async {
    try {
      await _client.rpc('presence_set_status', params: {
        'p_device_id': deviceId,
        'p_status': isOnline ? 'online' : 'offline',
      }).timeout(kProfileQueryTimeout);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<void> heartbeatPresence({required String deviceId}) async {
    try {
      await _client.rpc('presence_heartbeat', params: {'p_device_id': deviceId}).timeout(kProfileQueryTimeout);
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<int> fetchFriendsCount(String supabaseUid) async {
    try {
      final row = await _client
          .from('users')
          .select('friends_count')
          .eq('id', supabaseUid)
          .maybeSingle()
          .timeout(kProfileQueryTimeout);
      return row?['friends_count'] as int? ?? 0;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<int> fetchMutualGroupsCount(String otherSupabaseUid) async {
    try {
      final rows = await _client
          .from('chat_members')
          .select('chat_id, chats!inner(id, type)')
          .eq('user_id', otherSupabaseUid)
          .eq('chats.type', 'group')
          .isFilter('left_at', null)
          .timeout(kProfileQueryTimeout);
      return List<Map<String, dynamic>>.from(rows).length;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }

  @override
  Future<ProfileVisibility> fetchRelationshipStatus(String otherSupabaseUid) async {
    try {
      final myUid = _client.auth.currentUser?.id;
      if (myUid == null) return ProfileVisibility.nonFriend;

      final blocked = await _client
          .from('blocked_users')
          .select('blocker_id')
          .or('and(blocker_id.eq.$myUid,blocked_id.eq.$otherSupabaseUid),'
              'and(blocker_id.eq.$otherSupabaseUid,blocked_id.eq.$myUid)')
          .limit(1)
          .timeout(kProfileQueryTimeout);
      if (List.from(blocked).isNotEmpty) return ProfileVisibility.blocked;

      final friendship = await _client
          .from('friendships')
          .select('requester_id')
          .eq('status', 'accepted')
          .or('and(requester_id.eq.$myUid,addressee_id.eq.$otherSupabaseUid),'
              'and(requester_id.eq.$otherSupabaseUid,addressee_id.eq.$myUid)')
          .limit(1)
          .timeout(kProfileQueryTimeout);
      if (List.from(friendship).isNotEmpty) return ProfileVisibility.friend;

      return ProfileVisibility.nonFriend;
    } catch (e) {
      return _rethrowMapped(e);
    }
  }
}
