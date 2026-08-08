import '../repositories/notification_inbox_repository.dart';

class DeleteNotificationUseCase {
  final NotificationInboxRepository repository;
  const DeleteNotificationUseCase(this.repository);

  Future<void> call({required String uid, required String notificationId}) {
    return repository.deleteNotification(uid: uid, notificationId: notificationId);
  }
}
