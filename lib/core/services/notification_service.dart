import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Milestone 7.1 (Notification Foundation) — নোটিফিকেশন-সংক্রান্ত সব external
/// SDK-এর সাথে সরাসরি যোগাযোগের একমাত্র জায়গা। OfflineQueueManager /
/// ActiveChatTracker-এর মতোই singleton প্যাটার্ন অনুসরণ করা হয়েছে
/// (private constructor + static `.instance`), যাতে সারা অ্যাপে একটিই
/// FlutterLocalNotificationsPlugin ইনস্ট্যান্স ব্যবহৃত হয়।
///
/// Milestone 7.2 (Notification Handling) আপডেট: এই ক্লাস এখনো একমাত্র জায়গা
/// যেখান থেকে `flutter_local_notifications`/`firebase_messaging` SDK সরাসরি
/// কল হয় — `showNotification()` (local display) ও `onNotificationTapped`
/// (ট্যাপ payload স্ট্রিম) যোগ হয়েছে। FCM lifecycle wiring (onMessage/
/// onBackgroundMessage/getInitialMessage) এবং suppression-এর জন্য
/// `NotificationForegroundHandler`-এর reuse — এই দুটোই এখানে নয়, বরং
/// lib/core/services/fcm_message_handler.dart-এ (orchestration স্তর, এই
/// ক্লাসের ওপর নির্ভরশীল)। `NotificationForegroundHandler`
/// (lib/core/utils/notification_foreground_handler.dart) অপরিবর্তিত/অ-টাচড।
class NotificationService {
  NotificationService._privateConstructor();
  static final NotificationService instance = NotificationService._privateConstructor();

  // NOTE: Android notification channels are immutable once created on a
  // device — an app cannot change an existing channel's sound after the
  // fact (only the user can, via system settings). The original
  // 'pulse_default_channel' shipped with no sound override (implicit OS
  // default). Since this update adds a bundled sound, the id is bumped to
  // 'pulse_default_channel_v2' so it registers as a *new* channel with the
  // new sound baked in, rather than silently failing to apply to existing
  // installs. Old-channel cleanup is intentionally out of scope here
  // (channel deletion is a user-facing/DI concern, not a sound-routing one).
  static const String androidChannelId = 'pulse_default_channel_v2';
  static const String androidChannelName = 'Pulse Notifications';
  static const String androidChannelDescription = 'Pulse-এর মেসেজ ও সাধারণ নোটিফিকেশনের জন্য ডিফল্ট চ্যানেল।';

  /// res/raw/pulse_notification.mp3 — bundled sound for normal (non-alert)
  /// message notifications. Resource name must match the filename minus
  /// extension (Android raw-resource convention).
  static const String _defaultSoundResource = 'pulse_notification';

  /// Friend Alert Sounds: channel used when a custom sound was requested
  /// but is not available locally (not yet cached / cache lookup failed).
  /// res/raw/fallback_alert.mp3 — bundled sound for this tier.
  static const String alertFallbackChannelId = 'pulse_friend_alert_fallback_channel';
  static const String _alertFallbackSoundResource = 'fallback_alert';
  static const String _alertFallbackChannelName = 'Friend Alerts (Fallback Sound)';
  static const String _alertFallbackChannelDescription =
      'একটি Friend Alert Sound চাওয়া হয়েছিল কিন্তু কাস্টম অডিও লোকালি পাওয়া যায়নি — বান্ডলড fallback টোন ব্যবহার করা হয়।';

  /// Last-resort tier: used only if creating the fallback_alert.mp3 channel
  /// itself throws. Deliberately has no `sound:` override so the OS applies
  /// its own system default notification sound — this is the one tier that
  /// can never fail to produce *a* sound, since it depends on no bundled
  /// resource at all.
  static const String _alertSystemDefaultChannelId = 'pulse_friend_alert_system_default_channel';
  static const String _alertSystemDefaultChannelName = 'Friend Alerts (System Default Sound)';
  static const String _alertSystemDefaultChannelDescription =
      'Friend Alert Sound-এর কাস্টম ও fallback অডিও দুটোই ব্যবহার করা যায়নি — ডিভাইসের ডিফল্ট নোটিফিকেশন সাউন্ড ব্যবহার করা হয়।';
  bool _systemDefaultAlertChannelReady = false;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Bridges to MainActivity.kt's FileProvider helper — resolves a cached
  /// alert-audio file path to a content:// Uri, since the system
  /// notification/sound-playback process can't read a raw file:// path
  /// into this app's private storage on API 24+.
  static const MethodChannel _alertAudioUriChannel = MethodChannel('com.pulse.messenger/alert_audio_uri');

  bool _isInitialized = false;

  final Set<String> _createdAlertChannelIds = {};
  bool _fallbackAlertChannelReady = false;

  // Milestone 7.2 (Notification Handling) — local-notification ট্যাপ হলে তার
  // payload (chatId) এখানে emit হয়। broadcast করা হয়েছে যাতে একাধিক
  // listener নিরাপদে সাবস্ক্রাইব করতে পারে।
  final StreamController<String?> _notificationTapController = StreamController<String?>.broadcast();

  /// অ্যান্ড্রয়েড নোটিফিকেশন চ্যানেল তৈরি + local-notifications plugin init।
  /// Idempotent — একাধিকবার কল হলেও নিরাপদ (OfflineQueueManager.addToQueue-এর
  /// idempotent-safety নীতির অনুরূপ, যাতে ভবিষ্যতে একাধিক জায়গা থেকে কল হলেও
  /// পুনরায় চ্যানেল তৈরির চেষ্টা কোনো সমস্যা তৈরি না করে)।
  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidChannel = AndroidNotificationChannel(
      androidChannelId,
      androidChannelName,
      description: androidChannelDescription,
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound(_defaultSoundResource),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    // Milestone 7.2: ট্যাপ-নেভিগেশন এখন স্কোপে — local notification ট্যাপ হলে
    // payload স্ট্রিমে emit করা হয়। নেভিগেশন ডিসিশন এখানে নেওয়া হয় না, শুধু
    // payload এক্সপোজ করা হয় — FcmMessageHandler (core/services) তা consume
    // করে নেভিগেট করে।
    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _notificationTapController.add(response.payload);
      },
    );

    _isInitialized = true;
  }

  /// FCM পেলোড থেকে (foreground/background উভয় ক্ষেত্রে) একটি local
  /// notification প্রদর্শন করে। 7.1-এ তৈরি `androidChannelId`-ই ডিফল্ট হিসেবে
  /// ব্যবহৃত হয়; কাস্টম সাউন্ড দেওয়া হলে `_ensureAlertSoundChannel` একটি
  /// আলাদা চ্যানেল রিজলভ/তৈরি করে (Milestone 7.4)।
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? customSoundFilePath,
    String? alertId,
    String? soundChecksum,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Sound routing (Friend Alert Sounds cascade):
    //   1. customSoundFilePath present  -> per-alert channel, cached audio file.
    //   2. alertId present but no path  -> shared fallback channel, fallback_alert.mp3.
    //   3. neither (normal message)     -> default channel, pulse_notification.mp3.
    // Each tier that touches a bundled/cached resource is wrapped so a
    // channel-creation failure cascades to the next tier instead of losing
    // sound (and, at the innermost catch, instead of losing the notification).
    String channelId = androidChannelId;

    if (customSoundFilePath != null && alertId != null && soundChecksum != null) {
      try {
        channelId = await _ensureAlertSoundChannel(
          alertId: alertId,
          soundChecksum: soundChecksum,
          soundFilePath: customSoundFilePath,
        );
      } catch (_) {
        channelId = await _resolveFallbackAlertChannel();
      }
    } else if (alertId != null) {
      // Friend Alert was requested but no usable cached/custom audio path
      // was resolved upstream — go straight to the fallback tier.
      channelId = await _resolveFallbackAlertChannel();
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      androidChannelName,
      channelDescription: androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  Future<String> _ensureAlertSoundChannel({
    required String alertId,
    required String soundChecksum,
    required String soundFilePath,
  }) async {
    final String shortChecksum = soundChecksum.length > 8 ? soundChecksum.substring(0, 8) : soundChecksum;
    final String channelId = '${androidChannelId}_alert_${alertId}_$shortChecksum';

    if (_createdAlertChannelIds.contains(channelId)) {
      return channelId;
    }

    final String? contentUriString = await _alertAudioUriChannel.invokeMethod<String>(
      'getContentUri',
      {'path': soundFilePath},
    );
    if (contentUriString == null) {
      throw StateError('Could not resolve content:// Uri for alert audio at $soundFilePath');
    }

    final channel = AndroidNotificationChannel(
      channelId,
      androidChannelName,
      description: androidChannelDescription,
      importance: Importance.high,
      sound: UriAndroidNotificationSound(contentUriString),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _createdAlertChannelIds.add(channelId);
    return channelId;
  }

  /// Tier 2: shared channel using the bundled fallback_alert.mp3 raw
  /// resource. Created once and reused (unlike the per-alert custom-sound
  /// channels, this one doesn't vary per alertId/checksum). Falls through to
  /// tier 3 if channel creation itself throws.
  Future<String> _resolveFallbackAlertChannel() async {
    if (_fallbackAlertChannelReady) {
      return alertFallbackChannelId;
    }

    try {
      const channel = AndroidNotificationChannel(
        alertFallbackChannelId,
        _alertFallbackChannelName,
        description: _alertFallbackChannelDescription,
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound(_alertFallbackSoundResource),
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      _fallbackAlertChannelReady = true;
      return alertFallbackChannelId;
    } catch (_) {
      return _ensureSystemDefaultAlertChannel();
    }
  }

  /// Tier 3 (last resort): no `sound:` override, so Android applies the
  /// device's system default notification sound. Has nothing left to fall
  /// back to, so no try/catch — if this fails the notification still shows,
  /// just via whatever channelId was already in hand.
  Future<String> _ensureSystemDefaultAlertChannel() async {
    if (_systemDefaultAlertChannelReady) {
      return _alertSystemDefaultChannelId;
    }

    const channel = AndroidNotificationChannel(
      _alertSystemDefaultChannelId,
      _alertSystemDefaultChannelName,
      description: _alertSystemDefaultChannelDescription,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _systemDefaultAlertChannelReady = true;
    return _alertSystemDefaultChannelId;
  }

  /// ইউজার একটি local notification ট্যাপ করলে তার payload (chatId, বা null
  /// যদি payload ছাড়া পাঠানো হয়) emit করে।
  Stream<String?> get onNotificationTapped => _notificationTapController.stream;

  /// রানটাইম নোটিফিকেশন পারমিশন চাওয়া হয় (iOS-এ আবশ্যক, Android 13+-এও
  /// আবশ্যক)। ইতিমধ্যে গ্রান্ট/ডিনাই হয়ে থাকলে প্ল্যাটফর্ম নিজে থেকেই আগের
  /// সিদ্ধান্ত রিটার্ন করে — এখানে কোনো অতিরিক্ত ক্যাশিং লজিক যোগ করা হয়নি।
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// বর্তমান ডিভাইসের FCM token রিটার্ন করে (না থাকলে null)।
  Future<String?> getToken() {
    return _messaging.getToken();
  }

  /// FCM token রিফ্রেশ হলে (যেমন অ্যাপ রিইনস্টল বা ডেটা ক্লিয়ার) নতুন token
  /// এই স্ট্রিমে emit হয়। Firestore user-document-এ persist করার লজিক
  /// ইচ্ছাকৃতভাবে এই Foundation মাইলস্টোনে যোগ করা হয়নি (Firestore Schema
  /// টাচ না করার নিয়ম অনুযায়ী) — শুধু রিফ্রেশড token স্ট্রিম হিসেবে এক্সপোজ
  /// করা হলো, পরবর্তী মাইলস্টোনে কনজিউম করার জন্য প্রস্তুত।
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
