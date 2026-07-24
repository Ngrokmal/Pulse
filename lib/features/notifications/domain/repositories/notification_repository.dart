/// Milestone 7.1 (Notification Foundation) — ChatRepository/GroupRepository/
/// MediaRepository-এর কনভেনশন অনুসরণ করে: plain `Future`/`Stream` রিটার্ন করে
/// (AuthRepository-এর `Either<Failure, T>` প্যাটার্ন নয়, যা এই কোডবেসে শুধু
/// Auth ফিচারেই সীমাবদ্ধ) — এরর হলে core/errors/exceptions.dart-এর টাইপড
/// exception থ্রো হয়, কলার (UseCase/Bloc) তা catch করে।
abstract class NotificationRepository {
  /// Android notification channel তৈরি + local-notifications plugin init।
  Future<void> initialize();

  /// রানটাইম নোটিফিকেশন পারমিশন রিকোয়েস্ট করে; গ্রান্ট/প্রোভিশনাল হলে true।
  Future<bool> requestPermission();

  /// বর্তমান FCM token (না থাকলে null)।
  Future<String?> getFcmToken();

  /// FCM token রিফ্রেশ হলে নতুন token emit করা স্ট্রিম।
  Stream<String> get onFcmTokenRefresh;
}
