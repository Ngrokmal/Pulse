import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

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
