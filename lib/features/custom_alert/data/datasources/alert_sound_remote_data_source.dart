import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../models/friend_alert_sound_model.dart';

abstract class AlertSoundRemoteDataSource {
  Future<List<FriendAlertSoundEntity>> getGlobalSounds(String ownerUid);

  Future<List<FriendAlertSoundEntity>> getFriendSounds({
    required String ownerUid,
    required String friendUid,
  });

  Future<void> saveSound(FriendAlertSoundEntity sound);

  Future<void> deleteSound(FriendAlertSoundEntity sound);

  Future<List<Map<String, dynamic>>> fetchChangedSounds({
    required String ownerUid,
    required DateTime since,
  });
}

class AlertSoundRemoteDataSourceImpl implements AlertSoundRemoteDataSource {
  static const String _table = 'alert_sounds';

  final SupabaseClient supabase;

  const AlertSoundRemoteDataSourceImpl({required this.supabase});

  Future<String> _resolveUid(String firebaseUid) {
    return UserIdBridge.resolve(firebaseUid, currentSupabaseUserId: supabase.auth.currentUser?.id);
  }

  @override
  Future<List<FriendAlertSoundEntity>> getGlobalSounds(String ownerUid) async {
    try {
      final ownerId = await _resolveUid(ownerUid);
      final rows = await supabase.from(_table).select().eq('owner_id', ownerId).eq('scope', 'global');
      return List<Map<String, dynamic>>.from(rows)
          .map((row) => FriendAlertSoundModel.fromSupabaseRow(row, ownerUid: ownerUid))
          .toList();
    } catch (e) {
      throw ServerException(message: 'Failed to load global alert sounds: $e');
    }
  }

  @override
  Future<List<FriendAlertSoundEntity>> getFriendSounds({
    required String ownerUid,
    required String friendUid,
  }) async {
    try {
      final ownerId = await _resolveUid(ownerUid);
      final friendId = await _resolveUid(friendUid);
      final rows = await supabase
          .from(_table)
          .select()
          .eq('owner_id', ownerId)
          .eq('scope', 'friend')
          .eq('friend_id', friendId);
      return List<Map<String, dynamic>>.from(rows)
          .map((row) => FriendAlertSoundModel.fromSupabaseRow(row, ownerUid: ownerUid, friendUid: friendUid))
          .toList();
    } catch (e) {
      throw ServerException(message: 'Failed to load friend alert sounds: $e');
    }
  }

  @override
  Future<void> saveSound(FriendAlertSoundEntity sound) async {
    try {
      final model = FriendAlertSoundModel.fromEntity(sound);
      final ownerId = await _resolveUid(sound.ownerUid);
      final friendId = sound.isGlobal ? null : await _resolveUid(sound.friendUid!);
      final row = model.toSupabaseRow(ownerId: ownerId, friendId: friendId);
      await supabase.from(_table).upsert(row, onConflict: 'owner_id,alert_key');
    } catch (e) {
      throw ServerException(message: 'Failed to save alert sound: $e');
    }
  }

  @override
  Future<void> deleteSound(FriendAlertSoundEntity sound) async {
    try {
      final ownerId = await _resolveUid(sound.ownerUid);
      await supabase
          .from(_table)
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('owner_id', ownerId)
          .eq('alert_key', sound.alertId);
    } catch (e) {
      throw ServerException(message: 'Failed to delete alert sound: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedSounds({
    required String ownerUid,
    required DateTime since,
  }) async {
    try {
      final ownerId = await _resolveUid(ownerUid);
      final rows = await supabase
          .from(_table)
          .select()
          .eq('owner_id', ownerId)
          .gt('updated_at', since.toUtc().toIso8601String())
          .order('updated_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw ServerException(message: 'Failed to sync alert sounds: $e');
    }
  }
}
