import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../features/chat/data/datasources/chat_local_data_source.dart';
import '../../features/chat/data/datasources/message_inbox_applicator.dart';
import '../../features/chat/presentation/pages/chat_screen.dart';
import '../../features/custom_alert/data/models/alert_audio_metadata_model.dart';
import '../../features/custom_alert/domain/entities/alert_audio_metadata_entity.dart';
import '../../features/custom_alert/domain/usecases/get_instant_alert_audio_path_usecase.dart';
import '../di/injection_container.dart' as di;
import '../navigation/app_navigator_key.dart';
import '../utils/notification_foreground_handler.dart';
import '../utils/pending_chat_navigation.dart';
import 'alert_download_pipeline.dart';
import 'notification_service.dart';


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (!di.sl.isRegistered<AlertDownloadPipeline>()) {
    await di.init();
  }
  final data = message.data;
  final chatId = data['chatId'] as String?;
  final messageId = data['messageId'] as String?;
  if (chatId != null && messageId != null && data['id'] != null) {
    await MessageInboxApplicator(ChatLocalDataSourceImpl())
        .applyFromSupabaseRow(logicalChatId: chatId, row: Map<String, dynamic>.from(data));
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

  void wire() {
    if (_isWired) return;
    _isWired = true;

    _onMessageSub = FirebaseMessaging.onMessage.listen(displayNotificationIfNeeded);

    _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTapPayload(message.data['chatId'] as String?);
    });

    _onTapSub = NotificationService.instance.onNotificationTapped.listen(_handleTapPayload);
  }

  Future<void> displayNotificationIfNeeded(RemoteMessage message) async {
    final Map<String, dynamic> data = message.data;

    if (!NotificationForegroundHandler.instance.shouldDisplayNotification(data)) {
      return;
    }

    // MILESTONE 7 FIX: call pushes (`type: 'incoming_call'`/`'missed_call'`)
    // are sent as FCM notification+data hybrid messages — the OS already
    // renders the system-tray notification for them, and CallNotificationRouter
    // already owns routing taps on that notification (via onMessageOpenedApp /
    // getInitialMessage). Showing a second, local notification here — with no
    // callId in its payload, since this method only ever reads chatId — meant
    // that duplicate local notification was the one actually tapped, and its
    // tap silently no-op'd instead of reaching CallNotificationRouter at all.
    final String? pushType = data['type'] as String?;
    if (pushType == 'incoming_call' || pushType == 'missed_call') {
      return;
    }

    final chatId = data['chatId'] as String?;
    if (chatId != null && data.containsKey('id')) {
      unawaited(
        di.sl<MessageInboxApplicator>().applyFromSupabaseRow(
          logicalChatId: chatId,
          row: Map<String, dynamic>.from(data),
        ),
      );
    }

    final String title = message.notification?.title ?? (data['title'] as String?) ?? 'Pulse';
    final String body = message.notification?.body ?? (data['body'] as String?) ?? '';

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
      await di.sl<AlertDownloadPipeline>().run(alertAudio);
    }
  }

  Future<void> handleTerminatedLaunch() async {
    final RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    final String? chatId = initialMessage?.data['chatId'] as String?;
    if (chatId != null) {
      PendingChatNavigation.instance.setPendingChatId(chatId);
    }
  }

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
