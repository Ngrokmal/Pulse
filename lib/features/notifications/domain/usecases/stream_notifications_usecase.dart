import '../entities/notification_item_entity.dart';
import '../repositories/notification_inbox_repository.dart';

class StreamNotificationsUseCase {
  final NotificationInboxRepository repository;
  const StreamNotificationsUseCase(this.repository);

  Stream<List<NotificationItemEntity>> call(String uid) => repository.streamNotifications(uid);
}
