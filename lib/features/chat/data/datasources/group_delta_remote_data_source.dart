import 'package:supabase_flutter/supabase_flutter.dart';

class GroupDeltaRemoteDataSource {
  final SupabaseClient supabase;

  GroupDeltaRemoteDataSource({required this.supabase});

  Future<List<Map<String, dynamic>>> fetchGroupsInfoDelta({
    required List<String> groupIds,
    required DateTime since,
  }) async {
    if (groupIds.isEmpty) return const [];
    final rows = await supabase
        .from('chats')
        .select('id, name, creator_id, group_photo_url, group_photo_public_id, created_at, updated_at')
        .inFilter('id', groupIds)
        .gt('updated_at', since.toUtc().toIso8601String());
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchGroupMembersDelta({
    required List<String> groupIds,
    required DateTime since,
  }) async {
    if (groupIds.isEmpty) return const [];
    try {
      final rows = await supabase
          .from('chat_members')
          .select('chat_id, user_id, role, left_at, joined_at, updated_at')
          .inFilter('chat_id', groupIds)
          .gt('updated_at', since.toUtc().toIso8601String());
      return List<Map<String, dynamic>>.from(rows);
    } on PostgrestException catch (e) {
      final missingUpdatedAtColumn = (e.code == '42703') || e.message.contains('updated_at');
      if (!missingUpdatedAtColumn) rethrow;
      final rows = await supabase
          .from('chat_members')
          .select('chat_id, user_id, role, left_at, joined_at')
          .inFilter('chat_id', groupIds);
      return List<Map<String, dynamic>>.from(rows);
    }
  }
}
