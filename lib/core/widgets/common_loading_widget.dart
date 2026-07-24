import 'package:flutter/material.dart';

/// Stability + Loading milestone: প্রতিটি স্ক্রিনে আগে আলাদা আলাদা raw
/// `CircularProgressIndicator` ছিল (ChatScreen/GroupChatScreen/
/// GroupInfoScreen/HomeScreen-এ) — কোনো label নেই, কোনো retry নেই, এবং কোনো
/// timeout-fallback নেই (Firestore stream কখনো প্রথম snapshot না পাঠালে
/// এই স্পিনার চিরকাল ঘুরতেই থাকত — "infinite loading")।
///
/// এই একটি reusable widget সব "permanent" full-page loading state
/// (ChatLoading/GroupChatLoading/GroupInfoLoading-Initial/ChatListLoading)-এ
/// replace করে — কোনো নতুন প্যাকেজ লাগেনি, শুধু Material-এর
/// CircularProgressIndicator + optional retry button।
class CommonLoadingWidget extends StatelessWidget {
  /// লোডিং-এর নিচে দেখানো ঐচ্ছিক বার্তা (ডিফল্ট একটি সাধারণ বাংলা লেবেল)।
  final String message;

  /// দেওয়া হলে (Bloc-এর load timeout guard থেকে) একটি "আবার চেষ্টা করুন"
  /// বাটন দেখায় — চাপ দিলে caller-সরবরাহকৃত onRetry কল হয় (সাধারণত
  /// সংশ্লিষ্ট LoadXEvent পুনরায় dispatch করে)। null হলে শুধু স্পিনার+লেবেল।
  final VoidCallback? onRetry;

  const CommonLoadingWidget({
    super.key,
    this.message = 'লোড হচ্ছে…',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ],
      ),
    );
  }
}
