import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/call_state_entity.dart';
import '../../domain/entities/call_type.dart';
import '../cubit/call_cubit.dart';
import '../cubit/call_state.dart';
import '../cubit/incoming_call_listener_cubit.dart';
import '../models/call_end_summary.dart';
import '../widgets/call_background.dart';
import '../widgets/call_control_button.dart';
import '../widgets/call_peer_avatar.dart';
import 'active_call_screen.dart';
import 'call_ended_screen.dart';

/// Caller's "ringing" screen, shown immediately after tapping the call
/// button. Owns a freshly created [CallCubit] for the lifetime of this
/// call attempt.
class OutgoingCallScreen extends StatefulWidget {
  final String currentUserId;
  final String calleeId;
  final CallType callType;

  const OutgoingCallScreen({
    super.key,
    required this.currentUserId,
    required this.calleeId,
    required this.callType,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  late final CallCubit _cubit;
  late final IncomingCallListenerCubit _listenerCubit;

  /// MILESTONE 7 PART B: set once this screen has handed the call off
  /// normally — either forward to [ActiveCallScreen] (which takes over
  /// `_cubit` ownership via `BlocProvider.value`) or to
  /// [CallEndedScreen] (which closes `_cubit` itself). Guards [dispose]'s
  /// safety net below from double-closing/interfering with either path.
  bool _callHandled = false;

  @override
  void initState() {
    super.initState();
    _cubit = di.sl<CallCubit>();
    _listenerCubit = di.sl<IncomingCallListenerCubit>();
    // MILESTONE 7 PART B: mark busy for the outgoing/active-call
    // duration too — previously only `IncomingCallScreen` did this, so a
    // second incoming call while the user was calling out wasn't guarded
    // against (see `IncomingCallListenerCubit.isBusy` /
    // `CallNotificationRouter.routeIncomingCall`).
    _listenerCubit.setBusy(true);
    _cubit.startOutgoingCall(
      currentUserId: widget.currentUserId,
      calleeId: widget.calleeId,
      callType: widget.callType,
    );
  }

  @override
  void dispose() {
    // MILESTONE 7 PART B: safety net for abnormal removal — e.g. logout's
    // `pushAndRemoveUntil` tears down the whole stack, which disposes this
    // State without ever going through `_goToActiveCall`/`_goToEnded`.
    // Without this, `_cubit` would never close (leaking the Agora engine
    // and its subscriptions) and the busy flag would stay stuck `true`.
    if (!_callHandled) {
      _listenerCubit.setBusy(false);
      if (!_cubit.isClosed) {
        _cubit.close();
      }
    }
    super.dispose();
  }

  void _goToActiveCall() {
    // MILESTONE 7 PART C: the listener's condition (connecting/connected/
    // reconnecting) matches more than one phase in the normal join
    // sequence, and this screen's BlocConsumer stays mounted (and
    // listening on the same cubit `ActiveCallScreen` now also listens on)
    // for the duration of the pushReplacement transition — so without
    // this guard, a second matching state emitted mid-transition (e.g.
    // connecting -> connected) fired a second pushReplacement on top of
    // the first, corrupting the nav stack.
    if (_callHandled) return;
    _callHandled = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BlocProvider<CallCubit>.value(value: _cubit, child: const ActiveCallScreen()),
      ),
    );
  }

  void _goToEnded(CallState state) {
    // MILESTONE 7 PART C: same re-entry guard as `_goToActiveCall` above
    // — a redundant `ended` emission arriving before this screen is torn
    // down must not fire a second pushReplacement.
    if (_callHandled) return;
    _callHandled = true;
    final summary = CallEndSummary(
      peerDisplayName: state.peerDisplayName,
      peerAvatarUrl: state.peerAvatarUrl,
      status: state.session?.status,
      duration: state.elapsed,
      errorMessage: state.errorMessage,
    );
    _listenerCubit.setBusy(false);
    _cubit.close();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CallEndedScreen(summary: summary)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CallCubit>.value(
      value: _cubit,
      child: BlocConsumer<CallCubit, CallState>(
        listener: (context, state) {
          if (state.phase == CallPhase.connecting ||
              state.phase == CallPhase.connected ||
              state.phase == CallPhase.reconnecting) {
            _goToActiveCall();
          } else if (state.phase == CallPhase.ended) {
            _goToEnded(state);
          }
        },
        builder: (context, state) {
          return PopScope(
            canPop: false,
            child: CallBackground(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.large),
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.extraLarge),
                      Text(
                        state.callType == CallType.video ? 'Video Calling…' : 'Calling…',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                      ),
                      const Spacer(),
                      CallPeerAvatar(avatarUrl: state.peerAvatarUrl),
                      const SizedBox(height: AppSpacing.large),
                      Text(
                        state.peerDisplayName ?? '…',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: AppSpacing.small),
                      state.session == null
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                            )
                          : const Text('Ringing…', style: TextStyle(color: AppColors.textSecondary)),
                      const Spacer(),
                      CallControlButton(
                        icon: Icons.call_end_rounded,
                        label: 'Cancel',
                        backgroundColor: AppColors.error,
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _cubit.cancel();
                        },
                      ),
                      const SizedBox(height: AppSpacing.large),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
