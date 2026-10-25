import 'package:supabase_flutter/supabase_flutter.dart';

/// Call-flow counterpart to [PendingChatNavigation] (see
/// `pending_chat_navigation.dart`), same set/consume-once shape: holds a
/// tapped incoming-call notification's `callId` across the gap between the
/// tap happening — which, for a terminated-app launch, is before
/// `appNavigatorKey`'s navigator (or even `HomeScreen`) exists yet — and
/// the app being ready to actually route it. Consumed once from
/// `HomeScreen.initState`'s post-frame callback, right alongside the
/// existing `PendingChatNavigation` consumption.
class PendingCallNavigation {
  PendingCallNavigation._privateConstructor();
  static final PendingCallNavigation instance = PendingCallNavigation._privateConstructor();

  String? _pendingCallId;

  void setPendingCallId(String callId) {
    _pendingCallId = callId;
  }

  String? consumePendingCallId() {
    final id = _pendingCallId;
    _pendingCallId = null;
    return id;
  }

  String? resolveCurrentUserId() {
    return Supabase.instance.client.auth.currentUser?.id;
  }
}
