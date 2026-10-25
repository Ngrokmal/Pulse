import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class AlertForegroundServiceBridge {
  AlertForegroundServiceBridge._privateConstructor();
  static final AlertForegroundServiceBridge instance =
      AlertForegroundServiceBridge._privateConstructor();

  static const String _channelId = 'pulse_alert_download_status_channel';
  static const String _channelName = 'Friend Alert — Checking for Messages';
  static const String _channelDescription =
      'অস্থায়ী, চোখে দেখা যায় এমন স্ট্যাটাস — একটি নতুন Friend Alert অডিও '
      'ডাউনলোড/ভেরিফাই হওয়ার সময় সংক্ষিপ্তভাবে দেখা যায়। বিদ্যমান চ্যাট '
      'নোটিফিকেশন চ্যানেলগুলো (NotificationService) থেকে সম্পূর্ণ আলাদা —'
      'এখানে কোনো sound override নেই।';

  bool _isInitialized = false;

  void _ensureInitialized() {
    if (_isInitialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _isInitialized = true;
  }

  Future<void> start() async {
    _ensureInitialized();
    final bool alreadyRunning = await FlutterForegroundTask.isRunningService;
    if (alreadyRunning) return;

    await FlutterForegroundTask.startService(
      serviceId: 9101,
      notificationTitle: 'Pulse',
      notificationText: 'Checking for new messages…',
      notificationIcon: null,
      callback: _noopForegroundTaskCallback,
    );
  }

  Future<void> stop() async {
    try {
      final bool isRunning = await FlutterForegroundTask.isRunningService;
      if (!isRunning) return;
      await FlutterForegroundTask.stopService();
    } catch (_) {
    }
  }
}

@pragma('vm:entry-point')
void _noopForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopAlertTaskHandler());
}

class _NoopAlertTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
