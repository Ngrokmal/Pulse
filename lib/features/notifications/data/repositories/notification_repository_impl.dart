import '../../../../core/errors/exceptions.dart';
import '../../../../core/services/notification_service.dart';
import '../../domain/repositories/notification_repository.dart';

/// MediaRepositoryImpl-এর প্যাটার্নের অনুসরণ — data-লেয়ার সরাসরি একটি core
/// singleton service-এর (NotificationService) সাথে কথা বলে, আলাদা কোনো
/// "datasource" স্তর এই স্কোপের জন্য প্রয়োজন নেই (GroupRepositoryImpl/
/// MediaRepositoryImpl-এরও কোনো datasource নেই, একই সামঞ্জস্য বজায় রাখা হলো)।
/// সব external SDK কল (firebase_messaging, flutter_local_notifications)
/// NotificationService-এ ইতিমধ্যে encapsulated — এখানে শুধু error-mapping।
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
      return await notificationService.getToken();
    } catch (e) {
      throw ServerException(message: 'FCM token fetch failed: $e');
    }
  }

  @override
  Stream<String> get onFcmTokenRefresh => notificationService.onTokenRefresh;
}
