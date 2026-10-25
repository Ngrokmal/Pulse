import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Renders a live Agora video surface — local camera preview or a remote
/// peer's incoming video.
///
/// This is a deliberate, narrow exception to the "only
/// `agora_datasource_impl.dart` imports `agora_rtc_engine`" rule (Phase 1
/// §6): Agora's video surface is a platform view (`AgoraVideoView`) that
/// must be constructed directly from the live `RtcEngine` instance — no
/// Clean Architecture boundary can wrap that without losing the ability to
/// render video at all. To keep the blast radius minimal, only this one
/// widget file imports the SDK on the presentation side, and it receives
/// the engine as an untyped [engineHandle] (see
/// `AgoraRepository.engineHandle` / `CallCubit.rtcEngineHandle`) rather
/// than the Cubit or `CallState` ever holding a typed `RtcEngine` field.
///
/// MILESTONE 7 PART C: this is a [StatefulWidget], not a [StatelessWidget]
/// as originally written. `ActiveCallScreen`'s parent `BlocConsumer`
/// rebuilds once a second while connected (the elapsed-timer tick), plus
/// on every mute/camera/speaker toggle — a `StatelessWidget.build()`
/// constructing a brand-new [VideoViewController] every single time meant
/// a brand-new platform-view texture was registered every second, without
/// the previous one ever being disposed: a real, continuous resource leak
/// and a visible flicker source (each new controller re-attaches the
/// native surface). The [VideoViewController] is now created once — in
/// [initState], or when [engineHandle]/[channelId]/[remoteUid] actually
/// change — and explicitly disposed, so an unrelated rebuild (e.g. the
/// timer tick) reuses the existing controller and existing texture.
class AgoraVideoSurface extends StatefulWidget {
  /// The value of `CallCubit.rtcEngineHandle` — an `Object?` that is
  /// actually an `RtcEngine` once the engine has joined a channel, `null`
  /// otherwise.
  final Object? engineHandle;

  /// The Agora channel name currently joined. Required by
  /// [VideoViewController] for both local and remote surfaces.
  final String channelId;

  /// `null` for the local surface. The remote peer's Agora uid for the
  /// remote surface.
  final int? remoteUid;

  const AgoraVideoSurface.local({super.key, required this.engineHandle, required this.channelId})
      : remoteUid = null;

  const AgoraVideoSurface.remote({
    super.key,
    required this.engineHandle,
    required this.channelId,
    required int uid,
  }) : remoteUid = uid;

  @override
  State<AgoraVideoSurface> createState() => _AgoraVideoSurfaceState();
}

class _AgoraVideoSurfaceState extends State<AgoraVideoSurface> {
  VideoViewController? _controller;

  @override
  void initState() {
    super.initState();
    _buildController();
  }

  @override
  void didUpdateWidget(covariant AgoraVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // MILESTONE 7 PART C: only rebuild the controller when what it
    // actually points at changes — not on every unrelated CallState
    // rebuild (mute toggle, elapsed-timer tick, etc.).
    if (oldWidget.engineHandle != widget.engineHandle ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.remoteUid != widget.remoteUid) {
      _disposeController();
      _buildController();
    }
  }

  void _buildController() {
    final engine = widget.engineHandle;
    if (engine is! RtcEngine) {
      // Engine not yet joined (or already torn down) — caller is expected
      // to only mount this widget once `CallPhase.connected`/`connecting`
      // with a live handle, but this guards against the brief window
      // around join/leave.
      _controller = null;
      return;
    }

    final uid = widget.remoteUid;
    _controller = uid == null
        ? VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0))
        : VideoViewController.remote(
            rtcEngine: engine,
            canvas: VideoCanvas(uid: uid),
            connection: RtcConnection(channelId: widget.channelId),
          );
  }

  void _disposeController() {
    // MILESTONE 7 PART C: releases the platform-view texture this
    // controller registered — the piece the old per-build construction
    // never did for any but the very last controller created.
    unawaited(_controller?.dispose());
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const ColoredBox(color: AppColors.surface);
    }
    return AgoraVideoView(controller: controller);
  }
}
