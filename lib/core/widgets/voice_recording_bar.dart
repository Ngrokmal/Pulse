import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../../features/chat/data/services/voice_recording_coordinator.dart';
import '../../features/chat/domain/entities/voice_draft_entity.dart';
import 'voice_waveform_view.dart';

typedef VoiceDraftSentCallback = void Function(File file, Duration duration, List<double> waveform);

/// WhatsApp-style recording/draft bar (Bug 2, 4, 8). Replaces the text
/// composer entirely while a voice message is being recorded or sits
/// paused as a draft — mirrors WhatsApp: trash on the left, waveform +
/// timer in the middle, a Pause/Resume pill, and a green send circle on
/// the right. Driven entirely by [VoiceRecordingCoordinator]/[VoiceDraftStore]
/// so it reflects the true underlying recorder state even if this widget
/// was just (re)created — e.g. the user left the chat mid-recording and
/// came back.
class VoiceRecordingBar extends StatefulWidget {
  final String chatId;
  final String userId;
  final VoiceRecordingCoordinator coordinator;
  final VoiceDraftSentCallback onSend;
  final ValueChanged<String>? onError;

  const VoiceRecordingBar({
    super.key,
    required this.chatId,
    required this.userId,
    required this.coordinator,
    required this.onSend,
    this.onError,
  });

  @override
  State<VoiceRecordingBar> createState() => _VoiceRecordingBarState();
}

class _VoiceRecordingBarState extends State<VoiceRecordingBar> {
  Timer? _ticker;
  int _displayMs = 0;
  Stream<double>? _amplitudeStream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.coordinator.draftStore.draftNotifier.addListener(_onDraftChanged);
    _onDraftChanged();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.coordinator.draftStore.draftNotifier.removeListener(_onDraftChanged);
    super.dispose();
  }

  bool _matchesThisComposer(VoiceDraftEntity draft) => draft.chatId == widget.chatId && draft.userId == widget.userId;

  void _onDraftChanged() {
    if (!mounted) return;
    final draft = widget.coordinator.draftStore.current;
    _ticker?.cancel();
    _ticker = null;

    if (draft == null || !_matchesThisComposer(draft)) {
      _amplitudeStream = null;
      setState(() => _displayMs = 0);
      return;
    }

    if (draft.isPaused) {
      _amplitudeStream = null;
      setState(() => _displayMs = draft.elapsedMs);
      return;
    }

    // Live/resumed segment: cache the stream instance once (not re-read on
    // every rebuild) so VoiceWaveformView doesn't keep rebinding, and tick
    // the visible timer from the authoritative pause-aware elapsedMs.
    _amplitudeStream = widget.coordinator.recordingService.amplitudeStream;
    setState(() => _displayMs = widget.coordinator.recordingService.elapsedMs);
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _displayMs = widget.coordinator.recordingService.elapsedMs);
    });
  }

  Future<void> _togglePause() async {
    final draft = widget.coordinator.draftStore.current;
    if (draft == null || !_matchesThisComposer(draft) || draft.recoveredAfterRestart || _busy) return;
    setState(() => _busy = true);
    try {
      if (draft.isPaused) {
        await widget.coordinator.resumeRecording();
      } else {
        await widget.coordinator.pauseRecording();
      }
    } catch (e) {
      widget.onError?.call(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.coordinator.deleteDraft();
    } catch (e) {
      widget.onError?.call(e.toString());
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.coordinator.finalizeForSend();
      if (result == null) {
        widget.onError?.call('Recording was too short to send.');
        if (mounted) setState(() => _busy = false);
        return;
      }
      widget.onSend(result.file, result.duration, result.waveform);
    } catch (e) {
      widget.onError?.call(e.toString());
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _timeLabel {
    final d = Duration(milliseconds: _displayMs);
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.coordinator.draftStore.current;
    if (draft == null || !_matchesThisComposer(draft)) return const SizedBox.shrink();

    final isPaused = draft.isPaused;
    final canResume = !draft.recoveredAfterRestart;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _delete,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.inputBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isPaused ? AppColors.textSecondary : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_timeLabel, style: AppTypography.caption.copyWith(color: AppColors.textPrimary)),
                const SizedBox(width: 10),
                Expanded(
                  child: VoiceWaveformView(
                    isLive: !isPaused,
                    height: 22,
                    liveAmplitudeStream: _amplitudeStream,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: canResume ? _togglePause : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isPaused ? AppColors.whatsappGreen.withOpacity(0.15) : AppColors.inputBackground,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPaused ? Icons.mic_rounded : Icons.pause_rounded,
                  size: 18,
                  color: isPaused ? AppColors.whatsappGreen : AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                Text(
                  isPaused ? 'Resume' : 'Pause',
                  style: AppTypography.caption.copyWith(
                    color: isPaused ? AppColors.whatsappGreen : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _send,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.whatsappGreen, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
