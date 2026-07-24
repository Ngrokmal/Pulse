import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/profile/domain/entities/profile_entity.dart';
import '../../features/profile/domain/entities/verification_status.dart';
import '../../features/profile/domain/entities/privacy_settings.dart';

/// Local disk cache for another user's profile (name/bio/username/avatar/
/// online-status/lastSeen/etc.), keyed by uid.
///
/// Purpose (Phase-4 Task 2): the chat header must render instantly from
/// disk on open instead of waiting for a Firestore round-trip every single
/// time a chat is opened. `ProfileRepositoryImpl.streamProfile` still does
/// a live `.snapshots()` listener (unchanged, per "keep repositories") —
/// this cache sits in front of it purely for the *first paint*, and is
/// then kept in sync by writing every subsequent snapshot back to disk,
/// but ONLY when something in it actually changed (see [saveIfChanged]),
/// so we never do a redundant disk write for a profile that hasn't moved.
///
/// Profile pictures themselves are already disk-cached separately by
/// `cached_network_image` (see ProfileImageCache) — this service only
/// caches the *text/boolean fields*, plus the avatar *URL* (a string,
/// not the image bytes) so the existing image cache can be handed the
/// same URL immediately without waiting for Firestore either.
class FriendProfileCacheService {
  FriendProfileCacheService._();
  static final FriendProfileCacheService instance = FriendProfileCacheService._();

  static const String _keyPrefix = 'friend_profile_cache_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _prefsInstance() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Synchronous read is not possible before the first [warmUp] completes,
  /// so callers that need a value on the very first frame should call
  /// [warmUp] once near app start (see injection_container.dart), after
  /// which [getCachedSync] can be used safely from build methods.
  Future<void> warmUp() => _prefsInstance();

  /// Bug fix (cache must never leak between accounts): every entry is
  /// namespaced by the *currently signed-in* uid, not just the friend's
  /// uid. Previously the key was `friend_profile_cache_<friendUid>` only,
  /// so if account A and account B (same device) share a mutual friend,
  /// B would instantly see A's stale cached name/photo/online-status for
  /// that friend on first paint, before the live Firestore snapshot could
  /// correct it. Deriving the owner from `FirebaseAuth.instance.currentUser`
  /// here (instead of threading a viewer-uid param through every call
  /// site) means ChatAppBar/ProfileBloc need no changes — a different
  /// signed-in account transparently reads/writes a completely different
  /// key, so there is nothing to "leak" in the first place.
  String? _ownerScopedKey(String friendUid) {
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) return null; // no signed-in context — don't cache
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
      // Corrupt/old-shape cache entry — ignore, next Firestore snapshot
      // will repopulate it via saveIfChanged.
      return null;
    }
  }

  /// Writes the given profile to disk ONLY if it differs from what's
  /// already cached for this uid — this is the "never redownload/rewrite
  /// unchanged data" requirement. Comparing the encoded JSON string is a
  /// cheap, sufficient equality check here (no need for a field-by-field
  /// diff for a cache of this size).
  Future<void> saveIfChanged(ProfileEntity profile) async {
    final prefs = await _prefsInstance();
    final key = _ownerScopedKey(profile.uid);
    if (key == null) return; // no signed-in owner to scope this write to
    final encoded = jsonEncode(_toCacheJson(profile));
    final existing = prefs.getString(key);
    if (existing == encoded) return; // unchanged — skip the write entirely
    await prefs.setString(key, encoded);
  }

  /// Bug fix (logout → login as another account must invalidate stale
  /// presence): wipes every cached friend profile from disk. Owner-scoped
  /// keys already stop a *different* account from ever reading another
  /// account's entries (see [_ownerScopedKey]), but this is still called
  /// on sign-out (auth_remote_datasource.dart) as disk hygiene — otherwise
  /// every account that ever signs in on this device accumulates its own
  /// permanent set of cached entries in SharedPreferences forever.
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
