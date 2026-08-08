import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/profile/data/datasources/profile_local_data_source.dart';
import '../../features/profile/data/datasources/profile_remote_data_source.dart';
import '../../features/profile/data/models/profile_model.dart';
import '../supabase/user_id_bridge.dart';
import 'shared_presence_manager.dart';

class ProfileBulkWarmupService {
  final ProfileRemoteDataSource remoteDataSource;
  final ProfileLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final SharedPresenceManager presenceManager;

  ProfileBulkWarmupService({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.supabase,
    required this.presenceManager,
  });

  final Set<String> _warmedUids = {};

  Future<void> warmUpProfiles(Iterable<String> uids) async {
    try {
      final candidates = uids.toSet()..removeWhere((u) => u.isEmpty || _warmedUids.contains(u));
      if (candidates.isEmpty) return;

      final missing = <String>[];
      for (final uid in candidates) {
        final cached = await localDataSource.getCachedProfile(uid);
        if (cached != null) {
          _warmedUids.add(uid);
        } else {
          missing.add(uid);
        }
      }
      if (missing.isEmpty) return;

      final currentSupabaseUserId = supabase.auth.currentUser?.id;
      final Map<String, String> supabaseUidToUid = {};
      for (final uid in missing) {
        try {
          final supabaseUid = await UserIdBridge.resolve(uid, currentSupabaseUserId: currentSupabaseUserId);
          supabaseUidToUid[supabaseUid] = uid;
        } catch (_) {
        }
      }
      if (supabaseUidToUid.isEmpty) return;

      final supabaseUids = supabaseUidToUid.keys.toList();

      final userRowsFuture = remoteDataSource.fetchUserRowsBatch(supabaseUids);
      final presenceRowByIdFuture = presenceManager.primeWarmCache(supabaseUids);
      final userRows = await userRowsFuture;
      final presenceRowById = await presenceRowByIdFuture;

      final userRowById = {for (final row in userRows) row['id'] as String: row};

      final now = DateTime.now();
      for (final entry in supabaseUidToUid.entries) {
        final supabaseUid = entry.key;
        final uid = entry.value;
        final userRow = userRowById[supabaseUid];
        if (userRow == null) {
          _warmedUids.add(uid);
          continue;
        }
        final model = ProfileModel.fromSupabaseRows(
          uid: uid,
          userRow: userRow,
          presenceRow: presenceRowById[supabaseUid],
        );
        await localDataSource.cacheProfile(model);
        await localDataSource.setLastSyncedAt(uid, now);
        _warmedUids.add(uid);
      }
    } catch (e, st) {
      debugPrint('ProfileBulkWarmupService.warmUpProfiles failed (non-fatal): $e\n$st');
    }
  }
}
