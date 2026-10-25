import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/notifications/domain/usecases/get_fcm_token_usecase.dart';
import '../../features/notifications/domain/usecases/stream_fcm_token_refresh_usecase.dart';
import '../supabase/user_id_bridge.dart';
import '../utils/fcm_sync_diagnostics.dart';

class FcmTokenSyncService {
  final GetFcmTokenUseCase getFcmTokenUseCase;
  final StreamFcmTokenRefreshUseCase streamFcmTokenRefreshUseCase;
  final SupabaseClient supabase;

  FcmTokenSyncService({
    required this.getFcmTokenUseCase,
    required this.streamFcmTokenRefreshUseCase,
    required this.supabase,
  });

  StreamSubscription<String>? _refreshSubscription;
  String? _syncedUid;

  final Map<String, String> _lastWrittenTokenByUid = {};

  Future<void> syncFor(String uid) async {
    FcmSyncLog.step('syncFor', 'ENTER uid=$uid currentSupabaseAuthUser=${supabase.auth.currentUser?.id} '
        '_syncedUid=$_syncedUid hasLiveRefreshSubscription=${_refreshSubscription != null}');

    if (_syncedUid == uid && _refreshSubscription != null) {
      FcmSyncLog.step('syncFor', 'EARLY RETURN uid=$uid — already synced with a live refresh listener for this exact uid. '
          'This does NOT skip the write for a different uid.');
      return;
    }

    try {
      final token = await getFcmTokenUseCase();
      FcmSyncLog.step('syncFor', 'getFcmTokenUseCase() -> ${token == null ? 'NULL (no device token available yet)' : token}');
      if (token != null) {
        await _writeToken(uid, token);
      } else {
        FcmSyncLog.step('syncFor', 'SKIPPING write for uid=$uid — device token itself was null. '
            'This is a FirebaseMessaging/device-registration issue, not a Supabase issue.');
      }
    } catch (e, st) {
      FcmSyncLog.error('syncFor', 'Token fetch/write ultimately failed for uid=$uid after internal retries — swallowed by '
          'design (fire-and-forget). Will retry again on the next syncFor() call (next app open/resume/token refresh).', e, st);
    }

    await _refreshSubscription?.cancel();
    _syncedUid = uid;
    FcmSyncLog.step('syncFor', 'Subscribing onTokenRefresh listener for uid=$uid (previous subscription cancelled: '
        '${_refreshSubscription != null})');
    _refreshSubscription = streamFcmTokenRefreshUseCase().listen((newToken) {
      FcmSyncLog.step('onTokenRefresh', 'New token for uid=$uid: $newToken');
      _writeToken(uid, newToken).catchError((e, st) {
        FcmSyncLog.error('onTokenRefresh', 'write from refresh listener ultimately failed for uid=$uid after internal retries', e, st);
      });
    });
    FcmSyncLog.step('syncFor', 'EXIT uid=$uid');
  }

  static const int _maxWriteAttempts = 5;
  static const Duration _initialRetryDelay = Duration(milliseconds: 400);

  Future<void> _writeToken(String uid, String token) async {
    FcmSyncLog.step('writeToken', 'ENTER uid=$uid token=$token cachedTokenForThisUid=${_lastWrittenTokenByUid[uid]}');

    if (_lastWrittenTokenByUid[uid] == token) {
      FcmSyncLog.step('writeToken', 'EARLY RETURN uid=$uid — this uid already has this exact token cached as written. '
          'If the DB still shows NULL for this uid despite this log line, re-check with a fresh signOut so this cache '
          'is cleared (see resetForLogout) and retry.');
      return;
    }

    final bridgeMapped = await UserIdBridge.peek(uid);
    final supabaseUid = bridgeMapped ?? uid;
    FcmSyncLog.step(
      'UserIdBridge',
      'peek(uid=$uid) -> ${bridgeMapped ?? 'null (no mapping — using uid itself as the Supabase id)'}. '
      'Resolved supabaseUid=$supabaseUid',
    );

    Duration delay = _initialRetryDelay;
    for (int attempt = 1; attempt <= _maxWriteAttempts; attempt++) {
      FcmSyncLog.step(
        'writeToken',
        'Attempt $attempt/$_maxWriteAttempts — UPDATE public.users SET fcm_token=$token WHERE id=$supabaseUid '
        '(authenticated as currentSupabaseAuthUser=${supabase.auth.currentUser?.id})',
      );

      try {
        final result = await supabase.from('users').update({'fcm_token': token}).eq('id', supabaseUid).select('id, fcm_token');

        FcmSyncLog.step('writeToken', 'Attempt $attempt UPDATE returned ${result.length} row(s): $result');

        if (result.isNotEmpty) {
          _lastWrittenTokenByUid[uid] = token;
          FcmSyncLog.step('writeToken', 'SUCCESS uid=$uid supabaseUid=$supabaseUid token=$token on attempt $attempt '
              '(row confirmed updated)');
          return;
        }

        if (attempt == _maxWriteAttempts) {
          FcmSyncLog.step(
            'writeToken',
            'GIVING UP for uid=$uid after $_maxWriteAttempts attempts, all returned 0 rows for id=$supabaseUid. '
            'NOT caching this as written, so the next syncFor(uid=$uid) call (next app open/resume/token refresh) '
            'will retry from scratch.',
          );
          return;
        }
        FcmSyncLog.step('writeToken', 'Attempt $attempt matched 0 rows for id=$supabaseUid — retrying in ${delay.inMilliseconds}ms '
            '(row likely not visible yet — on_auth_user_created trigger race)');
      } catch (e, st) {
        if (attempt == _maxWriteAttempts) {
          FcmSyncLog.error(
            'writeToken',
            'GIVING UP for uid=$uid after $_maxWriteAttempts attempts, last attempt threw for supabaseUid=$supabaseUid. '
            'NOT caching this as written, so the next syncFor(uid=$uid) call will retry from scratch.',
            e,
            st,
          );
          rethrow;
        }
        FcmSyncLog.error('writeToken', 'Attempt $attempt threw for uid=$uid — retrying in ${delay.inMilliseconds}ms', e, st);
      }

      await Future.delayed(delay);
      final jitterMs = Random().nextInt(150);
      delay = Duration(milliseconds: min(delay.inMilliseconds * 2, 6000) + jitterMs);
    }
  }

  Future<void> resetForLogout() async {
    FcmSyncLog.step(
      'resetForLogout',
      'Sign-out detected — clearing all in-memory state. Before: _syncedUid=$_syncedUid '
      'hasLiveRefreshSubscription=${_refreshSubscription != null} '
      'cachedUids=${_lastWrittenTokenByUid.keys.toList()}',
    );
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    _syncedUid = null;
    _lastWrittenTokenByUid.clear();
    FcmSyncLog.step('resetForLogout', 'Cleared. Next syncFor() call for any uid will run as if this were a fresh app process.');
  }
}
