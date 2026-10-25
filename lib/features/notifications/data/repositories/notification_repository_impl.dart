import '../../../../core/errors/exceptions.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/fcm_sync_diagnostics.dart';
import '../../domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationService notificationService;

  const NotificationRepositoryImpl({required this.notificationService});

  @override
  Future<void> initialize() async {
    try {
      await notificationService.initialize();
    } catch (e) {
      throw ServerException(message: 'Notification initialize failed: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await notificationService.requestPermission();
    } catch (e) {
      throw ServerException(message: 'Notification permission request failed: $e');
    }
  }

  @override
  Future<String?> getFcmToken() async {
    try {
      final token = await notificationService.getToken();
      FcmSyncLog.step('NotificationRepositoryImpl', 'getFcmToken() -> $token');
      return token;
    } catch (e, st) {
      FcmSyncLog.error('NotificationRepositoryImpl', 'getFcmToken() threw', e, st);
      throw ServerException(message: 'FCM token fetch failed: $e');
    }
  }

  @override
  Stream<String> get onFcmTokenRefresh => notificationService.onTokenRefresh;
}
