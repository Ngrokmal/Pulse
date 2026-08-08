import 'package:flutter/material.dart';

import '../../../../core/navigation/app_navigator_key.dart';
import '../../../../core/utils/active_call_tracker.dart';
import '../../domain/entities/call_session_entity.dart';
import '../../domain/entities/call_type.dart';
import '../cubit/incoming_call_listener_cubit.dart';
import '../pages/incoming_call_screen.dart';
import '../pages/outgoing_call_screen.dart';

/// Centralizes call-screen navigation through the app's existing global
/// [appNavigatorKey] (the same navigator the FCM tap-to-open-chat flow in
/// `FcmMessageHandler` already uses), rather than routing through whatever
/// local [BuildContext] happens to trigger the call — this matters most
/// for [pushIncomingCall], which is driven by a background stream
/// listener with no natural local context of its own.
class CallNavigator {
  CallNavigator._();

  /// Pushes [IncomingCallScreen] for a ringing [session]. Called by the
  /// app-root `BlocListener` wired to `IncomingCallListenerCubit`, and by
  /// `CallNotificationRouter`'s FCM-tap path (MILESTONE 7) — the single
  /// choke point both go through, which is what makes the
  /// [ActiveCallTracker.hasRouted] guard below an effective de-dupe no
  /// matter which of the two callers gets here first.
  static void pushIncomingCall({
    required CallSessionEntity session,
    required String currentUserId,
    required IncomingCallListenerCubit listenerCubit,
  }) {
    if (ActiveCallTracker.instance.hasRouted(session.id)) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    ActiveCallTracker.instance.markRouted(session.id);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => IncomingCallScreen(
          session: session,
          currentUserId: currentUserId,
          listenerCubit: listenerCubit,
        ),
      ),
    );
  }

  /// Pushes [OutgoingCallScreen] to start a new call. Exposed for the
  /// (out-of-scope-for-this-milestone) call button that will eventually
  /// live on the chat/profile screens — kept here so that entry point has
  /// a single, consistent way to start a call once wired up.
  static void pushOutgoingCall({
    required String currentUserId,
    required String calleeId,
    required CallType callType,
  }) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => OutgoingCallScreen(
          currentUserId: currentUserId,
          calleeId: calleeId,
          callType: callType,
        ),
      ),
    );
  }
}
