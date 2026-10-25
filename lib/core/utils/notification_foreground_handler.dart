import '../../core/utils/active_call_tracker.dart';
import '../../core/utils/active_chat_tracker.dart';

class NotificationForegroundHandler {
  NotificationForegroundHandler._privateConstructor();
  static final NotificationForegroundHandler instance = NotificationForegroundHandler._privateConstructor();

  bool shouldDisplayNotification(Map<String, dynamic> messagePayload) {
    final String? incomingChatId = messagePayload['chatId'] as String?;
    
    if (incomingChatId != null) {
      final bool isScreenActive = ActiveChatTracker.instance.isChatActive(incomingChatId);
      if (isScreenActive) {
        return false;
      }
    }

    // MILESTONE 7: same suppression, for the call module's equivalent of
    // an "already-open screen" — a ringing call whose IncomingCallScreen
    // the realtime IncomingCallListenerCubit already pushed (typically
    // faster than this push arrives) doesn't need a second, redundant
    // system-tray notification for the same call.
    final String? type = messagePayload['type'] as String?;
    final String? incomingCallId = messagePayload['callId'] as String?;
    if (type == 'incoming_call' && incomingCallId != null) {
      final bool isCallScreenActive = ActiveCallTracker.instance.isCallActive(incomingCallId);
      if (isCallScreenActive) {
        return false;
      }
    }

    return true;
  }
}
