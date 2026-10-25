import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/chat/domain/services/voice_recording_service.dart';

class AlertSoundPlaybackButton extends StatefulWidget {
  final String audioUrl;
  final String displayName;
  final bool autoPlayOnce;
  final VoicePlaybackController Function() playbackControllerFactory;

  const AlertSoundPlaybackButton({
    super.key,
    required this.audioUrl,
    required this.displayName,
    required this.playbackControllerFactory,
    this.autoPlayOnce = false,
  });

  @override
  State<AlertSoundPlaybackButton> createState() => _AlertSoundPlaybackButtonState();
}

class _AlertSoundPlaybackButtonState extends State<AlertSoundPlaybackButton> {
  late final VoicePlaybackController _controller;
  StreamSubscription<bool>? _playingSub;
  bool _isPlaying = false;
  bool _hasAutoPlayed = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.playbackControllerFactory();
    _playingSub = _controller.isPlayingStream.listen(
      (playing) {
        if (!mounted) return;
        setState(() => _isPlaying = playing);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);
      },
    );
    if (widget.autoPlayOnce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoPlay());
    }
  }

  Future<void> _autoPlay() async {
    if (_hasAutoPlayed || !mounted) return;
    _hasAutoPlayed = true;
    try {
      await _controller.play(widget.audioUrl);
    } catch (_) {
    }
  }

  Future<void> _toggle() async {
    try {
      if (_isPlaying) {
        await _controller.pausePlayback();
      } else {
        await _controller.play(widget.audioUrl);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play "${widget.displayName}"')),
      );
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              _isPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            widget.displayName,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
