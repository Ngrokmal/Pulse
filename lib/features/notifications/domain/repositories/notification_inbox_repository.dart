import '../entities/notification_item_entity.dart';

abstract class NotificationInboxRepository {
  Stream<List<NotificationItemEntity>> streamNotifications(String uid);

  Stream<int> streamUnreadCount(String uid);

  Future<void> markAsRead({required String uid, required String notificationId});

  Future<void> markAllAsRead(String uid);

  Future<void> deleteNotification({required String uid, required String notificationId});

  Future<void> close();
}
