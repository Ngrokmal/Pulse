import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/profile/domain/entities/profile_entity.dart';
import '../../features/profile/domain/entities/verification_status.dart';
import '../../features/profile/domain/entities/privacy_settings.dart';

class FriendProfileCacheService {
  FriendProfileCacheService._();
  static final FriendProfileCacheService instance = FriendProfileCacheService._();

  static const String _keyPrefix = 'friend_profile_cache_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _prefsInstance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> warmUp() => _prefsInstance();

  String? _ownerScopedKey(String friendUid) {
    final ownerUid = Supabase.instance.client.auth.currentUser?.id;
    if (ownerUid == null) return null;
    return '$_keyPrefix${ownerUid}_$friendUid';
  }

  ProfileEntity? getCachedSync(String uid) {
    final prefs = _prefs;
    if (prefs == null) return null;
    final key = _ownerScopedKey(uid);
    if (key == null) return null;
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return _fromCacheJson(uid, map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIfChanged(ProfileEntity profile) async {
    final prefs = await _prefsInstance();
    final key = _ownerScopedKey(profile.uid);
    if (key == null) return;
    final encoded = jsonEncode(_toCacheJson(profile));
    final existing = prefs.getString(key);
    if (existing == encoded) return;
    await prefs.setString(key, encoded);
  }

  Future<void> clearAll() async {
    final prefs = await _prefsInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  Map<String, dynamic> _toCacheJson(ProfileEntity p) => {
        'username': p.username,
        'displayName': p.displayName,
        'bio': p.bio,
        'avatarUrl': p.avatarUrl,
        'avatarPublicId': p.avatarPublicId,
        'isOnline': p.isOnline,
        'lastSeen': p.lastSeen?.toIso8601String(),
        'verificationStatus': verificationStatusToString(p.verificationStatus),
        'lastSeenVisibility': privacyOptionToString(p.lastSeenVisibility),
        'onlineStatusVisibility': privacyOptionToString(p.onlineStatusVisibility),
      };

  ProfileEntity _fromCacheJson(String uid, Map<String, dynamic> json) {
    return ProfileEntity(
      uid: uid,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      avatarPublicId: json['avatarPublicId'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen'] as String) : null,
      verificationStatus: verificationStatusFromString(json['verificationStatus'] as String?),
      lastSeenVisibility: privacyOptionFromString(json['lastSeenVisibility'] as String?),
      onlineStatusVisibility: privacyOptionFromString(json['onlineStatusVisibility'] as String?),
    );
  }
}
