import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';

/// UI-polish pass (presentation-layer only): visual-only replacement for the
/// bare `Text('$name is typing…')` row already present in both chat screens.
/// Still takes a plain, already-computed label string — no change to how
/// `typingUserIds` is read or built from `ChatLoadedState`/
/// `GroupChatLoadedState`. AnimatedSize + AnimatedSwitcher give it a smooth
/// grow-in/fade instead of an abrupt SizedBox.shrink() <-> Text() flip.
class TypingIndicatorLabel extends StatelessWidget {
  final String? label;

  const TypingIndicatorLabel({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppDuration.medium,
      curve: Curves.easeOut,
      child: AnimatedSwitcher(
        duration: AppDuration.medium,
        child: label == null
            ? const SizedBox(width: double.infinity, height: 0)
            : Padding(
                key: ValueKey(label),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
