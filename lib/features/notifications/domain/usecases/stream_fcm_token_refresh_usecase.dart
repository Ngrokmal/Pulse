import '../repositories/notification_repository.dart';

/// StreamTypingStatusUseCase-এর মতোই পাতলা stream wrapper — কোনো অতিরিক্ত
/// ব্যবসায়িক লজিক নেই, শুধু NotificationRepository.onFcmTokenRefresh এক্সপোজ
/// করে। Persist-করার (Firestore user-document) লজিক ইচ্ছাকৃতভাবে এই
/// Foundation মাইলস্টোনে যোগ করা হয়নি।
class StreamFcmTokenRefreshUseCase {
  final NotificationRepository repository;
  const StreamFcmTokenRefreshUseCase(this.repository);

  Stream<String> call() {
    return repository.onFcmTokenRefresh;
  }
}
