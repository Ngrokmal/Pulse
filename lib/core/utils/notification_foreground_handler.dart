import '../../core/utils/active_chat_tracker.dart';

class NotificationForegroundHandler {
  NotificationForegroundHandler._privateConstructor();
  static final NotificationForegroundHandler instance = NotificationForegroundHandler._privateConstructor();

  /// ব্যাকগ্রাউন্ড বা ফোরগ্রাউন্ড FCM পেলোড রিসিভ করার পর এই মেথডটি কল হবে।
  /// বাগ ৫ ফিক্স: ইউজার যে চ্যাট স্ক্রিনে একটিভ আছে, তার নোটিফিকেশন ডিসপ্লে সাপ্রেস (Suppress) করা।
  bool shouldDisplayNotification(Map<String, dynamic> messagePayload) {
    final String? incomingChatId = messagePayload['chatId'] as String?;
    
    if (incomingChatId != null) {
      final bool isScreenActive = ActiveChatTracker.instance.isChatActive(incomingChatId);
      if (isScreenActive) {
        // ইউজার কারেন্টলি এই চ্যাট স্ক্রিনেই অবস্থান করছে -> নোটিফিকেশন পপ-আপ সাপ্রেস করুন
        return false;
      }
    }
    // ইউজার অন্য স্ক্রিনে আছে -> নোটিফিকেশন অ্যালার্ট প্রদর্শন করুন
    return true;
  }
}
