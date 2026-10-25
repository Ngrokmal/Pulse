import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';

abstract class ChatRemoteDataSource {
  Future<void> sendMessage({required String chatId, required Map<String, dynamic> messageData});

  Future<void> updateMessageText({required String messageId, required String text});

  Future<void> deleteMessage({required String messageId});

  Future<List<Map<String, dynamic>>> fetchMessages({required String chatId, int limit});

  Future<List<Map<String, dynamic>>> fetchMessagesBefore({
    required String chatId,
    required DateTime beforeCreatedAt,
    String? beforeId,
    int limit,
  });
}

class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final SupabaseClient _client;

  ChatRemoteDataSourceImpl({required SupabaseClient client}) : _client = client;

  @override
  Future<void> sendMessage({required String chatId, required Map<String, dynamic> messageData}) async {
    try {
      await _client.from('messages').insert({
        ...messageData,
        'chat_id': chatId,
      });
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
  Future<void> updateMessageText({required String messageId, required String text}) async {
    try {
      await _client.from('messages').update({'text': text}).eq('id', messageId);
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
  Future<void> deleteMessage({required String messageId}) async {
    try {
      await _client.from('messages').delete().eq('id', messageId);
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
  Future<List<Map<String, dynamic>>> fetchMessages({required String chatId, int limit = 50}) async {
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .limit(limit);
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
  Future<List<Map<String, dynamic>>> fetchMessagesBefore({
    required String chatId,
    required DateTime beforeCreatedAt,
    String? beforeId,
    int limit = 30,
  }) async {
    try {
      final beforeIso = beforeCreatedAt.toUtc().toIso8601String();
      var filterBuilder = _client
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .filter('deleted_at', 'is', null);

      if (beforeId != null) {
        filterBuilder = filterBuilder.or(
            'created_at.lt.$beforeIso,and(created_at.eq.$beforeIso,id.lt.$beforeId)');
      } else {
        filterBuilder = filterBuilder.lt('created_at', beforeIso);
      }

      final rows = await filterBuilder
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(limit);
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
}
