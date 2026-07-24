import 'dart:async';
import 'package:flutter/material.dart';
import '../../features/chat/domain/services/voice_recording_service.dart';

/// PHASE 3 FIX (receiver playback button + auto-play-once):
///
/// Before this widget, an incoming Friend Alert Sound message rendered as a
/// static, non-interactive `Row` (bell icon + name text) inside
/// `chat_screen.dart` — `message.alertAudioUrl` was persisted correctly by
/// `SendMessageWithAlertUseCase`/`ChatRepositoryImpl` but nothing on the
/// receiving side ever read it, so there was no way to play the sound and
/// no auto-play.
///
/// This widget renders a real tappable play/pause control bound to
/// [audioUrl], and — when [autoPlayOnce] is true (receiver, not the
/// sender's own message) — plays the sound exactly once, the first time
/// this widget mounts. Reuses the same `VoicePlaybackController`
/// abstraction already wired up for `VoiceMessageBubble` (see
/// `chat_screen.dart`'s `di.sl<VoicePlaybackController>()` factory
/// registration) — no new audio backend/package.
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
  // Guards against re-triggering on rebuilds (e.g. new messages arriving
  // causes ListView.builder to rebuild sibling items) — this widget instance
  // is only recreated if the ListView actually rebuilds this exact list
  // slot from scratch, so "once" here means "once per mount", which for a
  // message bubble means once per chat-screen session for that message.
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
      // Post-frame so this doesn't compete with the initial build/layout.
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoPlay());
    }
  }

  Future<void> _autoPlay() async {
    if (_hasAutoPlayed || !mounted) return;
    _hasAutoPlayed = true;
    try {
      await _controller.play(widget.audioUrl);
    } catch (_) {
      // Silent failure on auto-play — the tap control below is still
      // available as a manual fallback, so we don't surface a SnackBar
      // for something the user didn't explicitly request.
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
