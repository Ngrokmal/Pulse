import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';

/// UI-polish pass (presentation-layer only, Day 6 M3 follow-up):
/// visual-only replacement for the inline `message.status == 'read' ? ... :
/// ...` icon ternary that already existed in `chat_screen.dart` /
/// `group_chat_screen.dart`. Same three states, same meaning ('sent' /
/// 'delivered' / 'read' — values owned and written by the locked bloc/
/// repository layer) — this widget only decides how they're drawn, and
/// animates the swap with AnimatedSwitcher instead of an abrupt icon flip.
class MessageStatusIcon extends StatelessWidget {
  final String status;

  const MessageStatusIcon({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDuration.medium,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: _iconFor(status),
    );
  }

  Widget _iconFor(String status) {
    switch (status) {
      case 'read':
        // BUG FIX: previously rendered a plain filled dot (Icons.circle),
        // not a tick at all. WhatsApp-style read receipt = double check,
        // colored (blue/accent) to distinguish from delivered.
        return const Icon(
          Icons.done_all,
          key: ValueKey('status-read'),
          size: 14,
          color: AppColors.statusRead,
        );
      case 'delivered':
        // BUG FIX: previously colored with AppColors.statusRead (same as
        // "read"), making delivered indistinguishable from read. Delivered
        // should be grey — same tone as the single "sent" tick.
        return const Icon(
          Icons.done_all,
          key: ValueKey('status-delivered'),
          size: 14,
          color: AppColors.statusSent,
        );
      default:
        return const Icon(
          Icons.done,
          key: ValueKey('status-sent'),
          size: 14,
          color: AppColors.statusSent,
        );
    }
  }
}
