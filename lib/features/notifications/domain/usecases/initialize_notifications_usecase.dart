import '../repositories/notification_repository.dart';

class InitializeNotificationsUseCase {
  final NotificationRepository repository;
  const InitializeNotificationsUseCase(this.repository);

  Future<void> call() {
    return repository.initialize();
  }
}
