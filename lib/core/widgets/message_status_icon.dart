import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_duration.dart';

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
        return const Icon(
          Icons.done_all,
          key: ValueKey('status-read'),
          size: 14,
          color: AppColors.statusRead,
        );
      case 'delivered':
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
