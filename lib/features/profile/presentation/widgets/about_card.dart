import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class AboutCardRow {
  final IconData icon;
  final String label;
  final String value;
  const AboutCardRow({required this.icon, required this.label, required this.value});
}

/// Reusable "About" section — a rounded card listing icon+label+value
/// rows (location, join date, email, ...). Pure presentation.
class AboutCard extends StatelessWidget {
  final String title;
  final List<AboutCardRow> rows;

  const AboutCard({super.key, this.title = 'About', required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.medium),
      padding: const EdgeInsets.all(AppSpacing.medium),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.button,
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.small),
          for (int i = 0; i < rows.length; i++) ...[
            _AboutRow(row: rows[i]),
            if (i != rows.length - 1) const Divider(height: AppSpacing.medium),
          ],
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final AboutCardRow row;
  const _AboutRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: AppColors.inputBackground, shape: BoxShape.circle),
          child: Icon(row.icon, size: 16, color: AppColors.primaryAccent),
        ),
        const SizedBox(width: AppSpacing.small),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.label, style: AppTypography.caption),
              const SizedBox(height: 2),
              Text(row.value, style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}
