import '../repositories/notification_repository.dart';

/// পাতলা wrapper — NotificationRepository.requestPermission()-এর ওপর কোনো
/// অতিরিক্ত ব্যবসায়িক লজিক নেই।
class RequestNotificationPermissionUseCase {
  final NotificationRepository repository;
  const RequestNotificationPermissionUseCase(this.repository);

  Future<bool> call() {
    return repository.requestPermission();
  }
}
