import 'package:flutter/widgets.dart';

/// Milestone 7.2 (Notification Handling) — নোটিফিকেশন-ট্যাপ নেভিগেশনের জন্য
/// একটি গ্লোবাল নেভিগেটর কী। `MaterialApp.navigatorKey`-এ বসানো হয়
/// (lib/main.dart), যাতে কোনো BuildContext ছাড়াই (যেমন FCM
/// onMessageOpenedApp/local-notification-tap কলব্যাক থেকে, যেগুলোর নিজস্ব
/// কোনো widget context নেই) সরাসরি নেভিগেট করা যায়।
///
/// এটি নতুন কোনো রাউটিং সিস্টেম/আর্কিটেকচার তৈরি করে না — বিদ্যমান
/// `Navigator.of(context).push(MaterialPageRoute(...))` প্যাটার্নই (যা
/// HomeScreen/ChatScreen ইত্যাদিতে ইতিমধ্যে ব্যবহৃত) এই কী-এর
/// `currentState`-এর মাধ্যমে পুনরায় ব্যবহার হয়।
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
