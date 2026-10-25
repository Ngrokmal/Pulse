import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';

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
