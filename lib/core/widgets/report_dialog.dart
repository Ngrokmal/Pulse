import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Phase 8.6B (Moderation System)
///
/// Shared reason-picker used by Report User / Report Message / Report Group.
/// Purely presentational — returns the picked reason (+ optional
/// description) via Navigator.pop and lets the caller decide which
/// moderation usecase to invoke, so this widget stays reusable across
/// features without importing the admin module.
const List<String> reportReasons = [
  'Spam',
  'Harassment or bullying',
  'Hate speech',
  'Inappropriate content',
  'Impersonation',
  'Other',
];

class ReportSubmission {
  final String reason;
  final String? description;
  const ReportSubmission({required this.reason, this.description});
}

Future<ReportSubmission?> showReportDialog(
  BuildContext context, {
  required String title,
  bool includeDescription = false,
}) {
  String selectedReason = reportReasons.first;
  final descriptionController = TextEditingController();

  return showDialog<ReportSubmission>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  value: selectedReason,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.textPrimary),
                  items: reportReasons
                      .map((reason) => DropdownMenuItem(value: reason, child: Text(reason)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedReason = value);
                  },
                ),
                if (includeDescription) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'Additional details (optional)'),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  ReportSubmission(
                    reason: selectedReason,
                    description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                  ),
                ),
                child: const Text('Report'),
              ),
            ],
          );
        },
      );
    },
  );
}
