import 'package:hive_flutter/hive_flutter.dart';

import '../utils/fcm_sync_diagnostics.dart';

class UserIdBridge {
  UserIdBridge._();
  static const String _boxName = 'supabase_uid_bridge';
  static const String _reverseBoxName = 'supabase_uid_bridge_reverse';

  static Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  static Future<Box> _reverseBox() async {
    if (Hive.isBoxOpen(_reverseBoxName)) return Hive.box(_reverseBoxName);
    return Hive.openBox(_reverseBoxName);
  }

  static Future<void> link(String firebaseUid, String supabaseUserId) async {
    FcmSyncLog.step('UserIdBridge', 'link() called: firebaseUid=$firebaseUid -> supabaseUserId=$supabaseUserId '
        '(if this line never appears in the log for an account, link() is confirmed dead code for that account, '
        'as the current codebase-wide grep already shows — nothing calls it)');
    final box = await _box();
    await box.put(firebaseUid, supabaseUserId);
    final reverse = await _reverseBox();
    await reverse.put(supabaseUserId, firebaseUid);
  }

  static Future<String?> peek(String firebaseUid) async {
    final box = await _box();
    final result = box.get(firebaseUid) as String?;
    FcmSyncLog.step('UserIdBridge', 'peek(firebaseUid=$firebaseUid) -> $result | box "$_boxName" currently has '
        '${box.length} entr${box.length == 1 ? 'y' : 'ies'}: ${box.keys.toList()}');
    return result;
  }

  static Future<String?> reverseResolve(String supabaseUserId) async {
    final reverse = await _reverseBox();
    return reverse.get(supabaseUserId) as String?;
  }

  static Future<String> resolve(
    String firebaseUid, {
    String? currentSupabaseUserId,
  }) async {
    final mapped = await peek(firebaseUid);
    if (mapped != null) return mapped;
    if (firebaseUid.isNotEmpty) return firebaseUid;
    if (currentSupabaseUserId != null) return currentSupabaseUserId;
    FcmSyncLog.step('UserIdBridge', 'resolve() FAILED: no mapping, empty firebaseUid, and no currentSupabaseUserId fallback');
    throw StateError(
      'No Supabase user id mapped for Firebase uid "$firebaseUid", and no '
      'Supabase session is active. The Auth feature must sign this user '
      'into Supabase Auth (or call UserIdBridge.link) before chat data can '
      'be written under Supabase RLS — see PHASE2 manual setup notes.',
    );
  }
}
