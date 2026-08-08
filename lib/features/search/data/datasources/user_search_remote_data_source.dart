import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';

const int kUserSearchResultLimit = 30;
const Duration kUserSearchQueryTimeout = Duration(seconds: 15);

abstract class UserSearchRemoteDataSource {
  Future<List<Map<String, dynamic>>> searchUsers({
    required String query,
    required String excludeSupabaseUid,
    int limit = kUserSearchResultLimit,
  });
}

class UserSearchRemoteDataSourceImpl implements UserSearchRemoteDataSource {
  final SupabaseClient _client;

  UserSearchRemoteDataSourceImpl({required SupabaseClient client}) : _client = client;

  @override
  Future<List<Map<String, dynamic>>> searchUsers({
    required String query,
    required String excludeSupabaseUid,
    int limit = kUserSearchResultLimit,
  }) async {
    try {
      final rows = await _client.rpc('search_users', params: {
        'p_query': query,
        'p_exclude_id': excludeSupabaseUid,
        'p_limit': limit,
      }).timeout(kUserSearchQueryTimeout);
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
}
