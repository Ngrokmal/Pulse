import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../features/chat/presentation/pages/chat_screen.dart';
import '../../features/custom_alert/data/models/alert_audio_metadata_model.dart';
import '../../features/custom_alert/domain/entities/alert_audio_metadata_entity.dart';
import '../../features/custom_alert/domain/usecases/ensure_alert_audio_cached_usecase.dart';
import '../../features/custom_alert/domain/usecases/get_instant_alert_audio_path_usecase.dart';
import '../di/injection_container.dart' as di;
import '../navigation/app_navigator_key.dart';
import '../utils/notification_foreground_handler.dart';
import '../utils/pending_chat_navigation.dart';
import 'notification_service.dart';

/// Milestone 7.2 (Notification Handling).
///
/// এই ফাইলটি FCM মেসেজ লাইফসাইকেলের তিনটি অ্যাপ-স্টেট (foreground,
/// background, terminated) + ট্যাপ-নেভিগেশন ওয়্যার করার orchestration স্তর।
/// এটি নিজে কোনো external SDK সরাসরি কল করে না (শুধু listener/lifecycle
/// hook রেজিস্টার করে) — display-এর জন্য `NotificationService`
/// (lib/core/services/notification_service.dart) এবং suppression-এর জন্য
/// ইতিমধ্যে বিদ্যমান `NotificationForegroundHandler`
/// (lib/core/utils/notification_foreground_handler.dart) পুনরায় ব্যবহার করা
/// হয়েছে — এটি ডুপ্লিকেট করা হয়নি, টাচও করা হয়নি।
///
/// Chat/Group Chat/Offline Queue/Typing/Read Receipt/Delivery/Profile/
/// Firestore Schema — কোনোটাই টাচ করা হয়নি। ChatScreen শুধু তার বিদ্যমান
/// পাবলিক কনস্ট্রাক্টর (chatId, currentUserId) দিয়ে ব্যবহৃত হয়েছে, ঠিক
/// HomeScreen যেভাবে ব্যবহার করে (একই প্যাটার্ন পুনরায় ব্যবহার)।

/// FCM ব্যাকগ্রাউন্ড আইসোলেট হ্যান্ডলার — FCM-এর নিয়ম অনুযায়ী এটি অবশ্যই
/// top-level (non-class) ফাংশন হতে হবে, `main()`-এ
/// `FirebaseMessaging.onBackgroundMessage(...)`-এর মাধ্যমে রেজিস্টার করা
/// হয়। ব্যাকগ্রাউন্ড আইসোলেট মূল অ্যাপ আইসোলেট থেকে আলাদা, তাই Firebase
/// এখানে independently ইনিশিয়ালাইজ করতে হয়।
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (!di.sl.isRegistered<EnsureAlertAudioCachedUseCase>()) {
    await di.init();
  }
  await FcmMessageHandler.instance.displayNotificationIfNeeded(message);
}

class FcmMessageHandler {
  FcmMessageHandler._privateConstructor();
  static final FcmMessageHandler instance = FcmMessageHandler._privateConstructor();

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  StreamSubscription<String?>? _onTapSub;
  bool _isWired = false;

  /// Foreground listener (`onMessage`) + background-tap listener
  /// (`onMessageOpenedApp`) + local-notification-tap স্ট্রিম (
  /// `NotificationService.onNotificationTapped`) ওয়্যার করে। `main()`-এ
  /// একবার কল হওয়া উচিত। Idempotent — OfflineQueueManager-এর মতোই একাধিকবার
  /// কল হলেও নিরাপদ (পুনরায় সাবস্ক্রাইব হয় না)।
  void wire() {
    if (_isWired) return;
    _isWired = true;

    // App state: Foreground — অ্যাপ খোলা ও visible থাকা অবস্থায় FCM মেসেজ
    // এলে সিস্টেম নিজে থেকে কিছু দেখায় না, তাই ম্যানুয়ালি local notification
    // দেখাতে হয় (suppression logic-সহ, নিচে দেখুন)।
    _onMessageSub = FirebaseMessaging.onMessage.listen(displayNotificationIfNeeded);

    // App state: Background — অ্যাপ ব্যাকগ্রাউন্ডে থাকা অবস্থায় ইউজার সিস্টেম
    // নোটিফিকেশনে ট্যাপ করে অ্যাপ ফোরগ্রাউন্ডে আনলে এই স্ট্রিম ফায়ার করে।
    _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTapPayload(message.data['chatId'] as String?);
    });

    // আমরা নিজেরা ম্যানুয়ালি দেখানো local notification-এ ট্যাপ করলে (foreground
    // বা background handler থেকে দেখানো — উভয় ক্ষেত্রেই) এই স্ট্রিম দিয়ে আসে,
    // `onMessageOpenedApp` দিয়ে নয় (flutter_local_notifications-এর নিজস্ব
    // response callback)।
    _onTapSub = NotificationService.instance.onNotificationTapped.listen(_handleTapPayload);
  }

  /// FCM পেলোড থেকে local notification দেখানো উচিত কিনা যাচাই করে —
  /// `NotificationForegroundHandler.shouldDisplayNotification` পুনরায়
  /// ব্যবহার করে (বাগ ৫-এর active-chat suppression logic, ডুপ্লিকেট করা
  /// হয়নি) — এবং প্রয়োজনে `NotificationService.showNotification` দিয়ে
  /// দেখায়। Foreground listener ও ব্যাকগ্রাউন্ড আইসোলেট হ্যান্ডলার উভয়ই এই
  /// একই মেথড কল করে (কোনো ডুপ্লিকেট ডিসপ্লে-লজিক নেই)।
  Future<void> displayNotificationIfNeeded(RemoteMessage message) async {
    final Map<String, dynamic> data = message.data;

    if (!NotificationForegroundHandler.instance.shouldDisplayNotification(data)) {
      return;
    }

    final String title = message.notification?.title ?? (data['title'] as String?) ?? 'Pulse';
    final String body = message.notification?.body ?? (data['body'] as String?) ?? '';
    final String? chatId = data['chatId'] as String?;

    final AlertAudioMetadata? alertAudio = AlertAudioMetadataModel.fromPushData(data);
    String? instantSoundPath;
    if (alertAudio != null) {
      instantSoundPath = await di.sl<GetInstantAlertAudioPathUseCase>().call(alertAudio);
    }

    await NotificationService.instance.showNotification(
      id: _notificationIdFor(chatId),
      title: title,
      body: body,
      payload: chatId,
      customSoundFilePath: instantSoundPath,
      alertId: alertAudio?.alertId,
      soundChecksum: alertAudio?.checksum,
    );

    if (alertAudio != null && instantSoundPath == null) {
      try {
        await di.sl<EnsureAlertAudioCachedUseCase>().call(alertAudio);
      } catch (_) {}
    }
  }

  /// App state: Terminated — অ্যাপ সম্পূর্ণ বন্ধ থাকা অবস্থায় নোটিফিকেশনে
  /// ট্যাপ করে লঞ্চ হলে `getInitialMessage()`-এ সেটি পাওয়া যায় (একবারই,
  /// `main()`-এ `runApp()`-এর আগে চেক করা উচিত)। এই কোডবেসে auth সেশন
  /// persist হয় না, তাই সরাসরি নেভিগেট না করে chatId পরে consume করার জন্য
  /// pending হিসেবে সংরক্ষণ করা হয় (দেখুন PendingChatNavigation) — লগইনের পর
  /// HomeScreen সেটি consume করবে।
  Future<void> handleTerminatedLaunch() async {
    final RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    final String? chatId = initialMessage?.data['chatId'] as String?;
    if (chatId != null) {
      PendingChatNavigation.instance.setPendingChatId(chatId);
    }
  }

  /// App state: Background-tap ও local-notification-tap — উভয়েই এই একই
  /// মেথডে মিলিত হয় যাতে নেভিগেশন-ডিসিশন ডুপ্লিকেট না হয়। অ্যাপ ইতিমধ্যে
  /// রানিং (widget tree তৈরি) থাকায়, `appNavigatorKey`-এর context থেকে
  /// AuthCubit-এর বর্তমান state পড়া হয় — authenticated থাকলে সরাসরি
  /// ChatScreen-এ push করা হয়, নাহলে pending হিসেবে সংরক্ষণ করা হয় (লগইনের
  /// পর HomeScreen consume করবে — terminated-case-এর মতোই আচরণ)।
  void _handleTapPayload(String? chatId) {
    if (chatId == null) return;

    final NavigatorState? navigatorState = appNavigatorKey.currentState;
    final BuildContext? context = navigatorState?.context;

    if (navigatorState == null || context == null) {
      PendingChatNavigation.instance.setPendingChatId(chatId);
      return;
    }

    final String? currentUserId = PendingChatNavigation.instance.resolveCurrentUserId(context);
    if (currentUserId == null) {
      PendingChatNavigation.instance.setPendingChatId(chatId);
      return;
    }

    navigatorState.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId, currentUserId: currentUserId),
      ),
    );
  }

  int _notificationIdFor(String? chatId) {
    if (chatId == null) {
      return DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    }
    return chatId.hashCode & 0x7fffffff;
  }

  /// টেস্ট/হট-রিস্টার্ট সুবিধার্থে — বর্তমান অ্যাপ লাইফসাইকেলে ব্যবহার হয় না,
  /// কিন্তু `wire()`-এর subscription-গুলো সঠিকভাবে ক্লিনআপ করার সুযোগ রাখা
  /// হলো (OfflineQueueManager-এ কোনো dispose নেই, কিন্তু এখানে
  /// StreamSubscription থাকায় ভালো অভ্যাস হিসেবে যোগ করা হলো)।
  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _onTapSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedAppSub = null;
    _onTapSub = null;
    _isWired = false;
  }
}
