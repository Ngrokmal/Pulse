import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';

abstract class ChatListRemoteDataSource {
  Future<List<Map<String, dynamic>>> fetchChangedDirectChats({required DateTime since});

  Future<List<Map<String, dynamic>>> fetchUserInbox({
    required String userId,
    required DateTime since,
    int limit = 100,
  });

  Future<Map<String, dynamic>?> fetchLatestMessage(String remoteChatId);

  Future<Set<String>> fetchAcceptedFriendIds({required String userId});
}

class ChatListRemoteDataSourceImpl implements ChatListRemoteDataSource {
  final SupabaseClient _client;

  ChatListRemoteDataSourceImpl({required SupabaseClient client}) : _client = client;

  static const String _chatSelect = 'id, name, group_photo_url, last_message, '
      'last_message_at, last_message_sender_id, updated_at, '
      'chat_members(user_id, unread_count)';

  @override
  Future<List<Map<String, dynamic>>> fetchChangedDirectChats({required DateTime since}) async {
    try {
      final rows = await _client
          .from('chats')
          .select(_chatSelect)
          .eq('type', 'direct')
          .gt('updated_at', since.toUtc().toIso8601String())
          .order('updated_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    } on AuthException catch (e) {
      throw ServerException(message: e.message);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message);
    } on SocketException catch (e) {
      throw NetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw NetworkException(message: e.message ?? "Connection Timeout");
    } on PlatformException catch (e) {
      throw ServerException(message: e.message ?? "Platform Error");
    } catch (e) {
      throw UnknownException(message: e.toString());
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchUserInbox({
    required String userId,
    required DateTime since,
    int limit = 100,
  }) async {
    try {
      final rows = await _client.rpc('get_user_inbox', params: {
        'p_user_id': userId,
        'p_since': since.toUtc().toIso8601String(),
        'p_limit': limit,
      });
      return List<Map<String, dynamic>>.from(rows as List);
    } on AuthException catch (e) {
      throw ServerException(message: e.message);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message);
    } on SocketException catch (e) {
      throw NetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw NetworkException(message: e.message ?? "Connection Timeout");
    } on PlatformException catch (e) {
      throw ServerException(message: e.message ?? "Platform Error");
    } catch (e) {
      throw UnknownException(message: e.toString());
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchLatestMessage(String remoteChatId) async {
    try {
      final rows = await _client
          .from('messages')
          .select('id, text, type, file_name, sender_id, created_at')
          .eq('chat_id', remoteChatId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows);
      return list.isEmpty ? null : list.first;
    } on AuthException catch (e) {
      throw ServerException(message: e.message);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message);
    } on SocketException catch (e) {
      throw NetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw NetworkException(message: e.message ?? "Connection Timeout");
    } on PlatformException catch (e) {
      throw ServerException(message: e.message ?? "Platform Error");
    } catch (e) {
      throw UnknownException(message: e.toString());
    }
  }

  @override
  Future<Set<String>> fetchAcceptedFriendIds({required String userId}) async {
    try {
      final rows = await _client
          .from('friendships')
          .select('requester_id, addressee_id')
          .eq('status', 'accepted')
          .or('requester_id.eq.$userId,addressee_id.eq.$userId');
      final ids = <String>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final requester = row['requester_id'] as String?;
        final addressee = row['addressee_id'] as String?;
        if (requester != null && requester != userId) ids.add(requester);
        if (addressee != null && addressee != userId) ids.add(addressee);
      }
      return ids;
    } on AuthException catch (e) {
      throw ServerException(message: e.message);
    } on PostgrestException catch (e) {
      throw ServerException(message: e.message);
    } on SocketException catch (e) {
      throw NetworkException(message: e.message);
    } on TimeoutException catch (e) {
      throw NetworkException(message: e.message ?? "Connection Timeout");
    } on PlatformException catch (e) {
      throw ServerException(message: e.message ?? "Platform Error");
    } catch (e) {
      throw UnknownException(message: e.toString());
    }
  }
}
