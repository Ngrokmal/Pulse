import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';

abstract class NotificationRemoteDataSource {
  Future<List<Map<String, dynamic>>> fetchChangedNotifications({
    required String recipientId,
    required DateTime since,
  });

  Future<void> markAsRead({required String notificationId});

  Future<void> markAllAsRead({required String recipientId});

  Future<void> deleteNotification({required String notificationId});
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final SupabaseClient _client;

  NotificationRemoteDataSourceImpl({required SupabaseClient client}) : _client = client;

  T _mapError<T>(Object e) {
    if (e is AuthException) throw ServerException(message: e.message);
    if (e is PostgrestException) throw ServerException(message: e.message);
    if (e is SocketException) throw NetworkException(message: e.message);
    if (e is TimeoutException) throw NetworkException(message: e.message ?? 'Connection Timeout');
    if (e is PlatformException) throw ServerException(message: e.message ?? 'Platform Error');
    throw UnknownException(message: e.toString());
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedNotifications({
    required String recipientId,
    required DateTime since,
  }) async {
    try {
      final rows = await _client
          .from('notifications')
          .select()
          .eq('recipient_id', recipientId)
          .gt('updated_at', since.toUtc().toIso8601String())
          .order('updated_at', ascending: true)
          .order('id', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<void> markAsRead({required String notificationId}) async {
    try {
      await _client.from('notifications').update({'is_read': true}).eq('id', notificationId);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<void> markAllAsRead({required String recipientId}) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', recipientId)
          .eq('is_read', false);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<void> deleteNotification({required String notificationId}) async {
    try {
      await _client
          .from('notifications')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', notificationId);
    } catch (e) {
      return _mapError(e);
    }
  }
}
