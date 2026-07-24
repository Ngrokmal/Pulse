import '../repositories/notification_repository.dart';

/// পাতলা wrapper — NotificationRepository.getFcmToken()-এর ওপর কোনো
/// অতিরিক্ত ব্যবসায়িক লজিক নেই।
class GetFcmTokenUseCase {
  final NotificationRepository repository;
  const GetFcmTokenUseCase(this.repository);

  Future<String?> call() {
    return repository.getFcmToken();
  }
}
