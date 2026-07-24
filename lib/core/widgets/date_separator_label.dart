import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// WhatsApp-style centered date pill shown between messages sent on
/// different calendar days ("Today" / weekday name / "Month Day, Year" —
/// see lib/core/utils/time_formatter.dart:formatDateSeparator for the exact
/// day-boundary rules). Shared by ChatScreen and GroupChatScreen so the
/// rules and styling can't drift between the two screens.
class DateSeparatorLabel extends StatelessWidget {
  final String label;
  const DateSeparatorLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
