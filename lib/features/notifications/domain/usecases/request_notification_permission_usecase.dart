import '../repositories/notification_repository.dart';

class RequestNotificationPermissionUseCase {
  final NotificationRepository repository;
  const RequestNotificationPermissionUseCase(this.repository);

  Future<bool> call() {
    return repository.requestPermission();
  }
}
