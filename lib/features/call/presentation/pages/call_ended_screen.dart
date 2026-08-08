import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../models/call_end_summary.dart';
import '../widgets/call_background.dart';
import '../widgets/call_peer_avatar.dart';
import '../widgets/call_timer_text.dart';

/// Terminal screen shown briefly after a call ends, then auto-dismisses
/// back to whatever screen was beneath the call stack. Takes a plain
/// [CallEndSummary] rather than the (by now closed) `CallCubit`.
class CallEndedScreen extends StatefulWidget {
  final CallEndSummary summary;

  const CallEndedScreen({super.key, required this.summary});

  @override
  State<CallEndedScreen> createState() => _CallEndedScreenState();
}

class _CallEndedScreenState extends State<CallEndedScreen> {
  Timer? _autoCloseTimer;
  // MILESTONE 7 PART C: guards against a double pop — this screen's
  // pushReplacement transition (and the pop transition after it) takes
  // long enough for `mounted` to still be true if the user taps again
  // right as the auto-close timer fires, or double-taps quickly. Without
  // this, both calls to `_close` could pass the `mounted`/`canPop` checks
  // and pop twice, removing an extra screen underneath.
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _autoCloseTimer = Timer(const Duration(seconds: 2), _close);
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    final navigator = Navigator.of(context);
    // Each prior call screen (Outgoing/Incoming -> Active) replaced the one
    // before it via pushReplacement rather than stacking, so this screen
    // sits directly on top of whatever was on the stack before the call
    // started — a single pop returns there.
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return GestureDetector(
      onTap: _close,
      child: PopScope(
        canPop: true,
        child: CallBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CallPeerAvatar(avatarUrl: summary.peerAvatarUrl),
                  const SizedBox(height: AppSpacing.large),
                  Text(
                    summary.peerDisplayName ?? '',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.small),
                  Text(
                    summary.errorMessage ?? summary.headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                  if (summary.wasConnected) ...[
                    const SizedBox(height: AppSpacing.small),
                    CallTimerText(duration: summary.duration),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
