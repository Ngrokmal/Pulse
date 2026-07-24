import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// UI-polish pass (presentation-layer only, Day 6 M3 follow-up): replaces
/// the plain `ListTile` message rows in `chat_screen.dart` /
/// `group_chat_screen.dart` with a themed, shadowed bubble that fades +
/// slides in on first appearance. Takes only already-available display
/// data (text/isMe/timestamp/sender label/status widget) — no bloc,
/// repository, or entity type is imported here, so this stays reusable
/// regardless of which locked message model is behind it.
class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final String timeLabel;
  final String? senderLabel;
  final Widget? statusIcon;
  final Widget? mediaContent;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    required this.timeLabel,
    this.senderLabel,
    this.statusIcon,
    this.mediaContent,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AppDuration.medium,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.small,
            vertical: 4,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.small + 4,
            vertical: AppSpacing.small,
          ),
          decoration: BoxDecoration(
            color: isMe ? AppColors.bubbleMine : AppColors.bubbleTheirs,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 16),
            ),
            boxShadow: const [
              BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (senderLabel != null) ...[
                Text(
                  senderLabel!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              if (mediaContent != null) ...[
                mediaContent!,
                if (text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (text.isNotEmpty)
                Text(
                  text,
                  style: AppTypography.body.copyWith(color: AppColors.textPrimary),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(timeLabel, style: AppTypography.caption),
                  if (statusIcon != null) ...[
                    const SizedBox(width: 4),
                    statusIcon!,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
