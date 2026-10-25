import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/active_call_tracker.dart';
import '../../domain/entities/call_session_entity.dart';
import '../../domain/usecases/listen_incoming_call_usecase.dart';
import '../../domain/usecases/mark_call_busy_usecase.dart';
import '../../domain/usecases/reconcile_stale_calls_usecase.dart';
import 'incoming_call_listener_state.dart';

/// App-wide singleton (registered `lazySingleton`, started once from
/// `HomeScreen.initState` — the same `.start(uid)` pattern already used by
/// `NotificationBadgeCubit`) that watches Supabase for calls ringing
/// against the current user and surfaces them so the app root can push
/// `IncomingCallScreen` regardless of which screen is currently on top of
/// the navigation stack.
///
/// Not itself responsible for navigation (that's the app-root
/// `BlocListener` in `HomeScreen`, using `appNavigatorKey` per the
/// project's existing FCM-tap-to-navigate convention) or for the call's
/// own lifecycle once shown (that's `CallCubit`) — this cubit's only job
/// is "is something ringing for me right now", plus the busy-guard so a
/// second incoming call while the user is already on one gets an
/// automatic 'busy' response instead of interrupting the active call.
class IncomingCallListenerCubit extends Cubit<IncomingCallListenerState> {
  final ListenIncomingCallUseCase listenIncomingCallUseCase;
  final MarkCallBusyUseCase markCallBusyUseCase;
  final ReconcileStaleCallsUseCase reconcileStaleCallsUseCase;

  StreamSubscription<CallSessionEntity>? _subscription;
  bool _isBusy = false;
  String? _userId;

  IncomingCallListenerCubit({
    required this.listenIncomingCallUseCase,
    required this.markCallBusyUseCase,
    required this.reconcileStaleCallsUseCase,
  }) : super(const IncomingCallListenerIdle());

  void start(String userId) {
    _userId = userId;
    _subscription?.cancel();
    _subscription = listenIncomingCallUseCase.call(userId).listen(
      (session) {
        if (isClosed) return;
        if (_isBusy) {
          unawaited(markCallBusyUseCase.call(session.id));
          return;
        }
        emit(IncomingCallListenerRinging(session));
      },
      onError: (_) {},
    );
    // MILESTONE 6: covers cold/terminated-app launch — any call left
    // stale (ringing/accepted) from before this launch gets finalized
    // once, right as this device starts listening again. See
    // ReconcileStaleCallsUseCase for why this can't just be the existing
    // client-side ringing timeout.
    unawaited(reconcileStaleCallsUseCase.call(userId));
  }

  /// MILESTONE 6: called from the app-root `didChangeAppLifecycleState`
  /// resumed handler (`main.dart`, mirroring
  /// `GroupDeltaSyncCoordinator.instance.notifyAppResumed()`'s exact call
  /// site) — covers the background/foreground gap, as opposed to
  /// [start]'s cold-start coverage. A no-op before [start] has run once
  /// (nothing to reconcile against yet).
  void reconcileOnResume() {
    final userId = _userId;
    if (userId == null) return;
    unawaited(reconcileStaleCallsUseCase.call(userId));
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Set by the app root while an [ActiveCallScreen]/[OutgoingCallScreen]/
  /// [IncomingCallScreen] is on top of the stack, so a second incoming
  /// call is auto-declined as busy rather than shown.
  void setBusy(bool isBusy) {
    _isBusy = isBusy;
  }

  /// Public read side of [setBusy] — MILESTONE 7: lets
  /// `CallNotificationRouter` (an FCM-tap path with no local context of
  /// its own, same shape as this cubit's own realtime path) check whether
  /// the user is already on a call before trying to route a tapped
  /// notification to a second [IncomingCallScreen].
  bool get isBusy => _isBusy;

  /// Called once the ringing session currently being shown has been
  /// handled (accepted/declined/timed out/dismissed), so a stale
  /// [IncomingCallListenerRinging] state doesn't linger.
  void dismiss() {
    if (!isClosed && state is IncomingCallListenerRinging) {
      // MILESTONE 7: clears the ActiveCallTracker entry set when this
      // call's screen was pushed (see CallNavigator.pushIncomingCall), so
      // NotificationForegroundHandler stops treating this call as
      // on-screen once it's actually done. Deliberately does NOT remove
      // it from the de-dupe set itself — see ActiveCallTracker.clearActiveCall.
      final ringingState = state as IncomingCallListenerRinging;
      ActiveCallTracker.instance.clearActiveCall(ringingState.session.id);
      emit(const IncomingCallListenerIdle());
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
