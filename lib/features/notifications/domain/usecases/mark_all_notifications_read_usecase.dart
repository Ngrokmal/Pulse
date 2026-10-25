import '../repositories/notification_inbox_repository.dart';

class MarkAllNotificationsReadUseCase {
  final NotificationInboxRepository repository;
  const MarkAllNotificationsReadUseCase(this.repository);

  Future<void> call(String uid) => repository.markAllAsRead(uid);
}
