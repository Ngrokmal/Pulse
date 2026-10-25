import '../repositories/notification_inbox_repository.dart';

class MarkNotificationReadUseCase {
  final NotificationInboxRepository repository;
  const MarkNotificationReadUseCase(this.repository);

  Future<void> call({required String uid, required String notificationId}) {
    return repository.markAsRead(uid: uid, notificationId: notificationId);
  }
}
