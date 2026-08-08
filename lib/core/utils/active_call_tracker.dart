/// Call-flow counterpart to [ActiveChatTracker] (see
/// `active_chat_tracker.dart`), used by two different concerns that both
/// need to know about the current call screen:
///
/// 1. [NotificationForegroundHandler] — same job as it does for
///    `ActiveChatTracker`/chat notifications: suppress a redundant
///    system-tray "Incoming call" notification when the call it's for is
///    already on screen.
/// 2. [CallNavigator] — unlike a chat screen (which the user can
///    legitimately reopen many times), a given `callId` only ever rings
///    once, so this class doubles as the permanent de-dupe guard that
///    stops a call screen from ever being pushed twice for the same call
///    — whether the second attempt comes from `IncomingCallListenerCubit`'s
///    realtime stream firing again (e.g. a reconnect replay) or from
///    `CallNotificationRouter`'s FCM-tap path resolving the same call the
///    realtime listener already caught. [markRouted] is the single
///    write path both go through (inside `CallNavigator.pushIncomingCall`),
///    so neither caller has to coordinate with the other directly.
class ActiveCallTracker {
  ActiveCallTracker._privateConstructor();
  static final ActiveCallTracker instance = ActiveCallTracker._privateConstructor();

  final Set<String> _routedCallIds = {};
  String? _currentActiveCallId;

  /// True once [callId] has already been routed to a call screen, by
  /// either the realtime listener or an FCM tap — the de-dupe check.
  bool hasRouted(String callId) {
    return _routedCallIds.contains(callId);
  }

  /// Marks [callId] as routed and as the current on-screen call. Called
  /// once, right before actually pushing the call screen for it.
  void markRouted(String callId) {
    _routedCallIds.add(callId);
    _currentActiveCallId = callId;
  }

  /// True while [callId]'s screen is the one currently on top of the
  /// stack — the "is this call already visible" check.
  bool isCallActive(String callId) {
    return _currentActiveCallId == callId;
  }

  /// Called once the currently-shown call has been fully handled
  /// (accepted/declined/timed out/dismissed) — see
  /// `IncomingCallListenerCubit.dismiss()` — so [isCallActive] stops
  /// reporting a call that's no longer on screen. Deliberately does NOT
  /// remove [callId] from the routed set: that de-dupe guard must outlive
  /// the screen itself, since a call only ever rings once.
  void clearActiveCall(String callId) {
    if (_currentActiveCallId == callId) {
      _currentActiveCallId = null;
    }
  }
}
