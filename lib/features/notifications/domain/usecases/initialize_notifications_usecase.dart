import '../repositories/notification_repository.dart';

/// CreateGroupUseCase/AddMemberUseCase-এর মতোই পাতলা wrapper —
/// NotificationRepository.initialize()-এর ওপর কোনো অতিরিক্ত ব্যবসায়িক
/// লজিক নেই।
class InitializeNotificationsUseCase {
  final NotificationRepository repository;
  const InitializeNotificationsUseCase(this.repository);

  Future<void> call() {
    return repository.initialize();
  }
}
