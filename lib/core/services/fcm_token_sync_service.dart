import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/notifications/domain/usecases/get_fcm_token_usecase.dart';
import '../../features/notifications/domain/usecases/stream_fcm_token_refresh_usecase.dart';

/// Missing link identified by the notification-delivery audit: the app
/// already fetches an FCM token (GetFcmTokenUseCase /
/// StreamFcmTokenRefreshUseCase, both pre-existing but previously never
/// called anywhere) yet never persisted it, so the sender side had nothing
/// to read. This service is new and additive — it does not modify
/// NotificationService, the FCM receiver, or NotificationRepository; it only
/// calls their already-existing public methods and writes the result to
/// `users/{uid}.fcmToken`, which the new `sendMessageNotification` Cloud
/// Function reads.
class FcmTokenSyncService {
  final GetFcmTokenUseCase getFcmTokenUseCase;
  final StreamFcmTokenRefreshUseCase streamFcmTokenRefreshUseCase;
  final FirebaseFirestore firestore;

  FcmTokenSyncService({
    required this.getFcmTokenUseCase,
    required this.streamFcmTokenRefreshUseCase,
    required this.firestore,
  });

  /// Call once after a user is authenticated (see AuthGate in main.dart).
  /// Fire-and-forget by design — a failed token sync should never block app
  /// startup or navigation.
  Future<void> syncFor(String uid) async {
    try {
      final token = await getFcmTokenUseCase();
      if (token != null) {
        await _writeToken(uid, token);
      }
    } catch (_) {
      // Best-effort — push delivery degrades gracefully to "no push" rather
      // than blocking the user.
    }

    streamFcmTokenRefreshUseCase().listen((newToken) {
      _writeToken(uid, newToken).catchError((_) {});
    });
  }

  Future<void> _writeToken(String uid, String token) {
    return firestore.collection('users').doc(uid).set({'fcmToken': token}, SetOptions(merge: true));
  }
}
