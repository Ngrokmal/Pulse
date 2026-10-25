import '../../../../core/utils/fcm_sync_diagnostics.dart';
import '../repositories/notification_repository.dart';

class GetFcmTokenUseCase {
  final NotificationRepository repository;
  const GetFcmTokenUseCase(this.repository);

  Future<String?> call() async {
    final token = await repository.getFcmToken();
    FcmSyncLog.step('GetFcmTokenUseCase', 'call() -> $token');
    return token;
  }
}
