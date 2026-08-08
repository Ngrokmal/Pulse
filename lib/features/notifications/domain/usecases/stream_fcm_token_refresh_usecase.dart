import '../repositories/notification_repository.dart';

class StreamFcmTokenRefreshUseCase {
  final NotificationRepository repository;
  const StreamFcmTokenRefreshUseCase(this.repository);

  Stream<String> call() {
    return repository.onFcmTokenRefresh;
  }
}
