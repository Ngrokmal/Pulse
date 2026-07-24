import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Chat-screen floating bell that opens the Friend Alert Sounds bottom
/// sheet. Purely a visibility/animation widget — it owns no alert-sound
/// business logic (that lives in FriendAlertCubit/the bottom sheet).
///
/// Visibility rules (per spec):
///  - shown while [isComposerActive] is true (typing, recording, or the
///    composer has focus — the caller decides which of those apply)
///  - stays visible for [kBellLingerDuration] after the last time
///    [isComposerActive] flipped from true to false
///  - hidden on manual dismiss (long-press), screen close (widget
///    disposal), or once the linger window elapses with no interaction
///
/// Uses AnimatedOpacity for the fade — no sudden disappearance.
const Duration kBellLingerDuration = Duration(seconds: 20);

class FriendAlertBell extends StatefulWidget {
  final bool isComposerActive;
  final VoidCallback onTap;

  const FriendAlertBell({
    super.key,
    required this.isComposerActive,
    required this.onTap,
  });

  @override
  State<FriendAlertBell> createState() => _FriendAlertBellState();
}

class _FriendAlertBellState extends State<FriendAlertBell> {
  Timer? _lingerTimer;
  bool _visible = true;
  bool _manuallyDismissed = false;

  @override
  void initState() {
    super.initState();
    _armLingerTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant FriendAlertBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isComposerActive && !oldWidget.isComposerActive) {
      _lingerTimer?.cancel();
      _manuallyDismissed = false;
      if (!_visible) setState(() => _visible = true);
    } else if (!widget.isComposerActive && oldWidget.isComposerActive) {
      _armLingerTimerIfNeeded();
    }
  }

  void _armLingerTimerIfNeeded() {
    if (widget.isComposerActive || _manuallyDismissed) return;
    _lingerTimer?.cancel();
    _lingerTimer = Timer(kBellLingerDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _dismiss() {
    _manuallyDismissed = true;
    _lingerTimer?.cancel();
    setState(() => _visible = false);
  }

  @override
  void dispose() {
    _lingerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onLongPress: _dismiss,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
                tooltip: 'Friend Alert Sounds',
                onPressed: widget.onTap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
