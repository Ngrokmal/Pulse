import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../features/chat/data/services/voice_playback_coordinator.dart';
import '../../features/chat/domain/services/voice_recording_service.dart';
import 'voice_waveform_view.dart';

class VoiceMessageBubble extends StatefulWidget {
  final int durationMs;
  final List<double> waveform;
  final bool isMine;
  final String? mediaUrl;
  final VoicePlaybackController Function()? playbackControllerFactory;

  const VoiceMessageBubble({
    super.key,
    required this.durationMs,
    this.waveform = const [],
    this.isMine = false,
    this.mediaUrl,
    this.playbackControllerFactory,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  static const List<double> _speeds = [1.0, 1.5, 2.0];

  VoicePlaybackController? _controller;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  int _speedIndex = 0;

  bool get _isReady => widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty && widget.playbackControllerFactory != null;

  @override
  void initState() {
    super.initState();
    if (_isReady) {
      _controller = widget.playbackControllerFactory!.call();
      _positionSub = _controller!.positionStream.listen(
        (position) {
          if (!mounted) return;
          setState(() => _position = position);
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isPlaying = false);
        },
      );
      _playingSub = _controller!.isPlayingStream.listen(
        (playing) {
          if (!mounted) return;
          setState(() => _isPlaying = playing);
          if (!playing && _position >= Duration(milliseconds: widget.durationMs)) {
            setState(() => _position = Duration.zero);
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isPlaying = false);
        },
      );
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (_isPlaying) {
        await controller.pausePlayback();
      } else if (_position > Duration.zero && _position < Duration(milliseconds: widget.durationMs)) {
        // Bug 3 fix: about to resume audible playback — stop whatever
        // other voice message was playing first (WhatsApp: only one at a
        // time).
        await VoicePlaybackCoordinator.instance.setActive(controller);
        await controller.resumePlayback();
      } else {
        await VoicePlaybackCoordinator.instance.setActive(controller);
        await controller.play(widget.mediaUrl!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    }
  }

  Future<void> _cycleSpeed() async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _speedIndex = (_speedIndex + 1) % _speeds.length);
    try {
      controller.setSpeed(_speeds[_speedIndex]);
    } catch (_) {
      // non-fatal — speed label already updated, playback continues at previous rate
    }
  }

  void _seekToFraction(double fraction) {
    final controller = _controller;
    if (controller == null) return;
    final target = Duration(milliseconds: (widget.durationMs * fraction.clamp(0.0, 1.0)).round());
    try {
      controller.seekTo(target);
      setState(() => _position = target);
    } catch (_) {
      // non-fatal — ignore seek failure, keep current position
    }
  }

  String get _speedLabel {
    final speed = _speeds[_speedIndex];
    return speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';
  }

  double get _progress {
    if (widget.durationMs <= 0) return 0;
    return (_position.inMilliseconds / widget.durationMs).clamp(0, 1);
  }

  String get _timeLabel {
    final total = Duration(milliseconds: widget.durationMs);
    final remaining = total - _position;
    final safe = remaining.isNegative ? Duration.zero : remaining;
    final display = _isPlaying || _position > Duration.zero ? safe : total;
    final minutes = display.inMinutes;
    final seconds = display.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playingSub?.cancel();
    if (_controller != null) {
      VoicePlaybackCoordinator.instance.clearIfActive(_controller!);
    }
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _isReady ? _togglePlayback : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMine ? Colors.white24 : AppColors.primaryAccent.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: _isReady
                      ? (details) => _seekToFraction(details.localPosition.dx / constraints.maxWidth)
                      : null,
                  child: VoiceWaveformView(
                    amplitudes: widget.waveform,
                    progress: _progress,
                    height: 28,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(_timeLabel, style: AppTypography.caption.copyWith(color: AppColors.textPrimary)),
          if (_isReady) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _cycleSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_speedLabel, style: AppTypography.caption.copyWith(color: AppColors.textPrimary)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
