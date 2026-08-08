import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/call_session_entity.dart';
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

/// Callee's incoming-call screen, pushed by [CallNavigator.pushIncomingCall]
/// from the app-root listener wired to [IncomingCallListenerCubit].
class IncomingCallScreen extends StatefulWidget {
  final CallSessionEntity session;
  final String currentUserId;

  /// The global listener that surfaced this call — notified via
  /// [IncomingCallListenerCubit.dismiss] once handled, and marked busy
  /// while this screen (and whatever call screen follows it) is on top,
  /// so a second incoming call auto-declines as busy instead of
  /// interrupting this one.
  final IncomingCallListenerCubit listenerCubit;

  const IncomingCallScreen({
    super.key,
    required this.session,
    required this.currentUserId,
    required this.listenerCubit,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  late final CallCubit _cubit;

  /// MILESTONE 7 PART B: see the matching flag in `OutgoingCallScreen` —
  /// set once the call has been handed off normally (forward to
  /// [ActiveCallScreen] or to [CallEndedScreen]), guarding [dispose]'s
  /// safety net from double-closing `_cubit`.
  bool _callHandled = false;

  @override
  void initState() {
    super.initState();
    widget.listenerCubit.setBusy(true);
    _cubit = di.sl<CallCubit>();
    _cubit.presentIncomingCall(currentUserId: widget.currentUserId, incomingSession: widget.session);
  }

  @override
  void dispose() {
    widget.listenerCubit.dismiss();
    // MILESTONE 7 PART B: safety net for abnormal removal (e.g. logout's
    // `pushAndRemoveUntil` tearing down the whole stack) — without this,
    // a call that was still ringing/connecting when the stack was torn
    // down would never close `_cubit` (leaking the Agora engine) and
    // would leave the listener stuck "busy".
    if (!_callHandled) {
      widget.listenerCubit.setBusy(false);
      if (!_cubit.isClosed) {
        _cubit.close();
      }
    }
    super.dispose();
  }

  void _goToActiveCall() {
    // MILESTONE 7 PART C: see the matching guard in `OutgoingCallScreen` —
    // this screen's BlocConsumer can still be mounted and listening when
    // a second connecting/connected/reconnecting state arrives mid
    // pushReplacement transition, which would otherwise push
    // `ActiveCallScreen` a second time on top of the first.
    if (_callHandled) return;
    _callHandled = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BlocProvider<CallCubit>.value(value: _cubit, child: const ActiveCallScreen()),
      ),
    );
  }

  void _goToEnded(CallState state) {
    // MILESTONE 7 PART C: same re-entry guard as `_goToActiveCall` above.
    if (_callHandled) return;
    _callHandled = true;
    final summary = CallEndSummary(
      peerDisplayName: state.peerDisplayName,
      peerAvatarUrl: state.peerAvatarUrl,
      status: state.session?.status,
      duration: state.elapsed,
      errorMessage: state.errorMessage,
    );
    widget.listenerCubit.setBusy(false);
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
            // MILESTONE 7 PART B: previously cleared busy here, the
            // moment the call started connecting — which meant a second
            // incoming call could interrupt an already-active call. Busy
            // now stays `true` through the whole active call; it's
            // cleared once the call actually ends, in
            // `ActiveCallScreen._goToEnded` (or by this screen's own
            // `_goToEnded`/`dispose` if the call ends before connecting).
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
                        state.callType == CallType.video ? 'Incoming video call' : 'Incoming call',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                      ),
                      const Spacer(),
                      CallPeerAvatar(avatarUrl: state.peerAvatarUrl),
                      const SizedBox(height: AppSpacing.large),
                      Text(
                        state.peerDisplayName ?? '…',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          CallControlButton(
                            icon: Icons.call_end_rounded,
                            label: 'Decline',
                            backgroundColor: AppColors.error,
                            onPressed: state.isProcessing
                                ? null
                                : () {
                                    HapticFeedback.mediumImpact();
                                    _cubit.decline();
                                  },
                          ),
                          CallControlButton(
                            icon: Icons.call_rounded,
                            label: 'Accept',
                            backgroundColor: AppColors.whatsappGreen,
                            onPressed: state.isProcessing
                                ? null
                                : () {
                                    HapticFeedback.mediumImpact();
                                    _cubit.accept();
                                  },
                          ),
                        ],
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
