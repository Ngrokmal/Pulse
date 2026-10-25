import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../domain/entities/notification_item_entity.dart';

class NotificationTile extends StatelessWidget {
  final NotificationItemEntity notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  IconData get _icon {
    final type = notification.type.toLowerCase();
    if (type.contains('message') || type.contains('chat')) return Icons.chat_bubble_rounded;
    if (type.contains('friend') || type.contains('request')) return Icons.person_add_alt_1_rounded;
    if (type.contains('group')) return Icons.group_rounded;
    return Icons.notifications_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isRead = notification.isRead;
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: 2),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: 2),
        decoration: BoxDecoration(
          color: isRead ? AppColors.surface.withOpacity(0.5) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withOpacity(isRead ? 0.12 : 0.25),
            child: Icon(_icon, color: isRead ? AppColors.textSecondary : AppColors.primaryAccent),
          ),
          title: Text(
            notification.title?.isNotEmpty == true ? notification.title! : 'Notification',
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: isRead ? FontWeight.w400 : FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: notification.body?.isNotEmpty == true
              ? Text(
                  notification.body!,
                  style: AppTypography.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatChatListTimestamp(notification.createdAt), style: AppTypography.caption),
              if (!isRead) ...[
                const SizedBox(height: 6),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(color: AppColors.primaryAccent, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
