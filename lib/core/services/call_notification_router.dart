import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../features/call/domain/entities/call_status.dart';
import '../../features/call/domain/usecases/listen_call_status_usecase.dart';
import '../../features/call/presentation/cubit/incoming_call_listener_cubit.dart';
import '../../features/call/presentation/navigation/call_navigator.dart';
import '../di/injection_container.dart' as di;
import '../navigation/app_navigator_key.dart';
import '../utils/active_call_tracker.dart';
import '../utils/pending_call_navigation.dart';

/// Routes taps on call-related push notifications, mirroring
/// [FcmMessageHandler]'s exact wiring shape (`wire()` /
/// `handleTerminatedLaunch()`, driven by `onMessageOpenedApp` /
/// `getInitialMessage()`) but call-specific.
///
/// The payload shape this reads (`type`: `'incoming_call'` |
/// `'missed_call'`, plus `callId`/`callerId`/...) is the exact one
/// `CallRepositoryImpl.createCall`/`.markMissed` already send via the
/// shared `PushNotificationSenderService` — see those two call sites for
/// the authoritative key list. Both are sent as FCM notification+data
/// hybrid messages (see `send-push-notification` Edge Function), so unlike
/// chat pushes, a tap on a backgrounded/terminated call notification is
/// always the *system* tray notification Android displayed itself — hence
/// `onMessageOpenedApp`/`getInitialMessage()` are the two relevant taps
/// here; there's no local (`flutter_local_notifications`) re-display for
/// calls to also wire a tap stream for.
///
/// Deliberately NOT responsible for showing the ringing UI itself: an
/// `incoming_call` tap resolves the still-live [CallSessionEntity] via
/// [ListenCallStatusUseCase] and hands off to the exact same
/// `CallNavigator.pushIncomingCall` the realtime `IncomingCallListenerCubit`
/// uses, so [ActiveCallTracker]'s de-dupe guard inside `CallNavigator` is
/// the single source of truth no matter which path gets there first — this
/// matters because `subscribeToIncomingCalls` (the realtime path) only
/// sees *new* inserts, so a cold/background-launch tap for a call that
/// started ringing before this device was listening is the only way that
/// device ever finds out about it.
class CallNotificationRouter {
  CallNotificationRouter._privateConstructor();
  static final CallNotificationRouter instance = CallNotificationRouter._privateConstructor();

  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  bool _isWired = false;

  void wire() {
    if (_isWired) return;
    _isWired = true;

    _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTapPayload(message.data);
    });
  }

  Future<void> handleTerminatedLaunch() async {
    final RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    final data = initialMessage?.data;
    if (data == null) return;

    final String? type = data['type'] as String?;
    final String? callId = data['callId'] as String?;
    if (type == 'incoming_call' && callId != null) {
      // Mirrors FcmMessageHandler.handleTerminatedLaunch's exact
      // shape: at this point in app startup there's no navigator (or
      // signed-in user) to route to yet, so this is unconditionally
      // deferred to PendingCallNavigation for HomeScreen to consume.
      PendingCallNavigation.instance.setPendingCallId(callId);
    }
    // 'missed_call': no call-log screen exists yet to deep-link into
    // (out of scope for this milestone — see the matching note on
    // CallRepositoryImpl.markMissed's push) — nothing further to do
    // beyond letting the app launch normally.
  }

  void _handleTapPayload(Map<String, dynamic> data) {
    final String? type = data['type'] as String?;
    final String? callId = data['callId'] as String?;
    if (type != 'incoming_call' || callId == null) return;

    final navigatorState = appNavigatorKey.currentState;
    final currentUserId = PendingCallNavigation.instance.resolveCurrentUserId();

    if (navigatorState == null || currentUserId == null) {
      PendingCallNavigation.instance.setPendingCallId(callId);
      return;
    }

    unawaited(routeIncomingCall(callId: callId, currentUserId: currentUserId));
  }

  /// Resolves [callId] to its live session and, if it's still actually
  /// ringing, hands off to `CallNavigator.pushIncomingCall`. Shared by the
  /// live-tap path above and by `HomeScreen`'s `PendingCallNavigation`
  /// consumption, so both go through the exact same guards.
  Future<void> routeIncomingCall({required String callId, required String currentUserId}) async {
    final listenerCubit = di.sl<IncomingCallListenerCubit>();

    // Already on another call — the realtime listener's own busy-guard
    // handles marking this call busy; nothing for the tap to route to.
    if (listenerCubit.isBusy) return;

    // Cheap short-circuit before the network round-trip below: the
    // realtime listener (or an earlier tap) may have already routed this
    // exact call. `CallNavigator.pushIncomingCall` re-checks this same
    // guard right before pushing, so this is purely an optimization, not
    // the source of truth.
    if (ActiveCallTracker.instance.hasRouted(callId)) return;

    try {
      final session = await di.sl<ListenCallStatusUseCase>().call(callId).first;
      if (session.status != CallStatus.ringing) return;
      CallNavigator.pushIncomingCall(
        session: session,
        currentUserId: currentUserId,
        listenerCubit: listenerCubit,
      );
    } catch (_) {
      // Best-effort: a resolve failure (e.g. a transient network blip)
      // just means this tap doesn't route — the realtime listener remains
      // the primary path and will still catch the call if it's genuinely
      // still ringing by the time it (re)connects.
    }
  }

  void dispose() {
    _onMessageOpenedAppSub?.cancel();
    _onMessageOpenedAppSub = null;
    _isWired = false;
  }
}
