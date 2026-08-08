import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/call_state_entity.dart';
import '../cubit/call_cubit.dart';
import '../cubit/call_state.dart';
import '../cubit/incoming_call_listener_cubit.dart';
import '../models/call_end_summary.dart';
import '../widgets/agora_video_surface.dart';
import '../widgets/call_background.dart';
import '../widgets/call_control_button.dart';
import '../widgets/call_peer_avatar.dart';
import '../widgets/call_timer_text.dart';
import 'call_ended_screen.dart';

/// Connected (or connecting/reconnecting) call screen. Reads its
/// [CallCubit] from context — the owning Incoming/Outgoing screen forwards
/// its existing cubit instance via `BlocProvider<CallCubit>.value` when
/// pushing this route, rather than this screen creating its own.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _navigatedToEnded = false;
  late final CallCubit _cubit;

  @override
  void initState() {
    super.initState();
    // Captured once for `dispose`'s safety net below — `context.read` is
    // safe here since `BlocProvider<CallCubit>` (from the owning
    // Incoming/OutgoingCallScreen) is already an ancestor by the time this
    // State is created.
    _cubit = context.read<CallCubit>();
  }

  @override
  void dispose() {
    // MILESTONE 7 PART B: safety net mirroring
    // Incoming/OutgoingCallScreen's — e.g. logout's `pushAndRemoveUntil`
    // tearing down the stack mid-call would otherwise leave `_cubit` open
    // (Agora engine + subscriptions leaked) and the listener stuck
    // "busy" forever, since neither `_goToEnded` nor the owning screen's
    // own dispose runs in that case.
    if (!_navigatedToEnded) {
      di.sl<IncomingCallListenerCubit>().setBusy(false);
      if (!_cubit.isClosed) {
        _cubit.close();
      }
    }
    super.dispose();
  }

  void _goToEnded(BuildContext context, CallCubit cubit, CallState state) {
    if (_navigatedToEnded) return;
    _navigatedToEnded = true;
    final summary = CallEndSummary(
      peerDisplayName: state.peerDisplayName,
      peerAvatarUrl: state.peerAvatarUrl,
      status: state.session?.status,
      duration: state.elapsed,
      errorMessage: state.errorMessage,
    );
    // MILESTONE 7 PART B: this screen is reached once a call has
    // connected, which is also the point at which
    // Incoming/OutgoingCallScreen stopped owning the busy flag (it now
    // stays `true` for the whole active call — see those files) — so
    // clearing it on the *this* screen's own end path is what actually
    // resets it for a call that made it to "connected".
    di.sl<IncomingCallListenerCubit>().setBusy(false);
    cubit.close();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CallEndedScreen(summary: summary)),
    );
  }

  String _phaseLabel(CallPhase phase) {
    switch (phase) {
      case CallPhase.connecting:
      case CallPhase.accepted:
        return 'Connecting…';
      case CallPhase.reconnecting:
        return 'Reconnecting…';
      case CallPhase.connected:
        return '';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CallCubit>();
    return BlocConsumer<CallCubit, CallState>(
      listener: (context, state) {
        if (state.phase == CallPhase.ended) {
          _goToEnded(context, cubit, state);
        }
      },
      builder: (context, state) {
        final isVideo = state.isVideoCall;
        return PopScope(
          canPop: false,
          child: CallBackground(
            child: SafeArea(
              child: Stack(
                children: [
                  if (isVideo)
                    _VideoLayer(cubit: cubit, state: state)
                  else
                    const SizedBox.shrink(),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.large),
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.medium),
                        if (!isVideo) ...[
                          const Spacer(),
                          CallPeerAvatar(avatarUrl: state.peerAvatarUrl),
                          const SizedBox(height: AppSpacing.large),
                        ] else
                          const Spacer(flex: 3),
                        Text(
                          state.peerDisplayName ?? '…',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.small),
                        state.phase == CallPhase.connected
                            ? CallTimerText(duration: state.elapsed)
                            : Text(
                                _phaseLabel(state.phase),
                                style: const TextStyle(color: AppColors.textSecondary),
                              ),
                        const Spacer(),
                        _ControlsRow(cubit: cubit, state: state),
                        const SizedBox(height: AppSpacing.medium),
                        CallControlButton(
                          icon: Icons.call_end_rounded,
                          label: 'End',
                          backgroundColor: AppColors.error,
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            cubit.endCall();
                          },
                        ),
                        const SizedBox(height: AppSpacing.large),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Composites the remote peer's video fullscreen with the local camera as
/// a small picture-in-picture in the top-right corner — the standard
/// two-party video-call layout. Falls back to the gradient + avatar
/// placeholder whenever a live surface isn't available yet (engine not
/// joined, or the remote peer hasn't published video — e.g. mid-connect,
/// or the peer has their camera off), so the screen never shows a blank
/// or broken platform view.
class _VideoLayer extends StatelessWidget {
  final CallCubit cubit;
  final CallState state;
  const _VideoLayer({required this.cubit, required this.state});

  @override
  Widget build(BuildContext context) {
    final channelId = state.session?.channelName;
    final remoteUid = state.remoteParticipant?.agoraUid;
    final engine = cubit.rtcEngineHandle;
    final showRemoteVideo = engine != null && channelId != null && remoteUid != null && state.isConnected;
    final showLocalPreview = engine != null && channelId != null && state.isCameraOn && state.isVideoCall;

    return Positioned.fill(
      child: Stack(
        children: [
          if (showRemoteVideo)
            AgoraVideoSurface.remote(engineHandle: engine, channelId: channelId, uid: remoteUid)
          else
            _VideoPlaceholder(avatarUrl: state.peerAvatarUrl),
          if (showLocalPreview)
            Positioned(
              top: AppSpacing.large,
              right: AppSpacing.large,
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AgoraVideoSurface.local(engineHandle: engine, channelId: channelId),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gradient + avatar shown in place of remote video before the engine has
/// joined, before the peer has published video, or if the live surface is
/// momentarily unavailable (e.g. right around join/leave or reconnect).
class _VideoPlaceholder extends StatelessWidget {
  final String? avatarUrl;
  const _VideoPlaceholder({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.backgroundBottom],
        ),
      ),
      child: Center(child: CallPeerAvatar(avatarUrl: avatarUrl, size: 96)),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  final CallCubit cubit;
  final CallState state;

  const _ControlsRow({required this.cubit, required this.state});

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      CallControlButton(
        icon: state.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
        label: 'Mute',
        isActive: state.isMuted,
        onPressed: () {
          HapticFeedback.selectionClick();
          cubit.toggleMute();
        },
      ),
      CallControlButton(
        icon: state.isSpeakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
        label: 'Speaker',
        isActive: state.isSpeakerOn,
        onPressed: () {
          HapticFeedback.selectionClick();
          cubit.toggleSpeaker();
        },
      ),
      if (state.isVideoCall) ...[
        CallControlButton(
          icon: state.isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
          label: 'Camera',
          isActive: !state.isCameraOn,
          onPressed: () {
            HapticFeedback.selectionClick();
            cubit.toggleCamera();
          },
        ),
        CallControlButton(
          icon: Icons.cameraswitch_rounded,
          label: 'Switch',
          onPressed: () {
            HapticFeedback.selectionClick();
            cubit.switchCamera();
          },
        ),
      ],
    ];

    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: controls);
  }
}
