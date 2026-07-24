import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/presentation/models/profile_ui_data.dart';
import '../../../profile/presentation/widgets/verification_badge.dart';

class SearchResultTile extends StatelessWidget {
  final ProfileEntity profile;
  final VoidCallback onTap;

  const SearchResultTile({super.key, required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = ProfileUiData.fromEntity(profile);
    final hasAvatar = data.avatarUrl != null && data.avatarUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.2),
          backgroundImage: hasAvatar ? NetworkImage(data.avatarUrl!) : null,
          child: hasAvatar ? null : const Icon(Icons.person, color: AppColors.textPrimary),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                data.name,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            VerificationBadge(status: data.verificationStatus, size: 14),
          ],
        ),
        subtitle: Text(
          data.username,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        onTap: onTap,
      ),
    );
  }
}
