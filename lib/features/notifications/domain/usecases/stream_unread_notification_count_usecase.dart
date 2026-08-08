import '../repositories/notification_inbox_repository.dart';

class StreamUnreadNotificationCountUseCase {
  final NotificationInboxRepository repository;
  const StreamUnreadNotificationCountUseCase(this.repository);

  Stream<int> call(String uid) => repository.streamUnreadCount(uid);
}
