import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// BUG FIX (mic button did nothing): this used to require a long-press-and-
/// hold gesture to start recording at all, with the whole WhatsApp-style
/// recording UI (waveform/timer/pause/delete/send) built inline inside this
/// same widget only while held down. Per the Voice Message audit spec, a
/// single tap now starts recording immediately, and the recording/paused
/// controls live in a separate always-visible [VoiceRecordingBar] (driven by
/// [VoiceRecordingCoordinator]) so they survive this widget being torn down
/// and rebuilt — e.g. the composer swaps mic → send/back as text is typed,
/// or the user briefly navigates away and back.
///
/// This widget is intentionally "dumb": it only renders the idle mic icon
/// and reports a tap. All actual start/pause/resume/delete/send logic lives
/// in VoiceRecordingCoordinator so there is a single source of truth (no
/// duplicated recording logic).
class MicRecordButton extends StatelessWidget {
  final VoidCallback onTap;

  const MicRecordButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_none_rounded, color: Colors.white),
      ),
    );
  }
}
