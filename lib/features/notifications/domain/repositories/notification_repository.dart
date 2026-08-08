abstract class NotificationRepository {
  Future<void> initialize();

  Future<bool> requestPermission();

  Future<String?> getFcmToken();

  Stream<String> get onFcmTokenRefresh;
}
