import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/fcm_sync_diagnostics.dart';

class NotificationService {
  NotificationService._privateConstructor();
  static final NotificationService instance = NotificationService._privateConstructor();

  static const String androidChannelId = 'pulse_default_channel_v2';
  static const String androidChannelName = 'Pulse Notifications';
  static const String androidChannelDescription = 'Pulse-এর মেসেজ ও সাধারণ নোটিফিকেশনের জন্য ডিফল্ট চ্যানেল।';

  static const String _defaultSoundResource = 'pulse_notification';

  static const String alertFallbackChannelId = 'pulse_friend_alert_fallback_channel';
  static const String _alertFallbackSoundResource = 'fallback_alert';
  static const String _alertFallbackChannelName = 'Friend Alerts (Fallback Sound)';
  static const String _alertFallbackChannelDescription =
      'একটি Friend Alert Sound চাওয়া হয়েছিল কিন্তু কাস্টম অডিও লোকালি পাওয়া যায়নি — বান্ডলড fallback টোন ব্যবহার করা হয়।';

  static const String _alertSystemDefaultChannelId = 'pulse_friend_alert_system_default_channel';
  static const String _alertSystemDefaultChannelName = 'Friend Alerts (System Default Sound)';
  static const String _alertSystemDefaultChannelDescription =
      'Friend Alert Sound-এর কাস্টম ও fallback অডিও দুটোই ব্যবহার করা যায়নি — ডিভাইসের ডিফল্ট নোটিফিকেশন সাউন্ড ব্যবহার করা হয়।';
  bool _systemDefaultAlertChannelReady = false;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const MethodChannel _alertAudioUriChannel = MethodChannel('com.pulse.messenger/alert_audio_uri');

  bool _isInitialized = false;

  final Set<String> _createdAlertChannelIds = {};
  bool _fallbackAlertChannelReady = false;

  final StreamController<String?> _notificationTapController = StreamController<String?>.broadcast();

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

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _notificationTapController.add(response.payload);
      },
    );

    _isInitialized = true;
  }

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

  Stream<String?> get onNotificationTapped => _notificationTapController.stream;

  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<String?> getToken() async {
    final token = await _messaging.getToken();
    FcmSyncLog.step('NotificationService', 'FirebaseMessaging.instance.getToken() -> $token');
    return token;
  }

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
