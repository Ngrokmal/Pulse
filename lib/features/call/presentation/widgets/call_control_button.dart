import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Circular icon button used for the in-call controls row (mute, speaker,
/// camera, switch camera, end call). [isActive] fills the button (e.g.
/// mute currently on); otherwise it renders as a translucent outline.
class CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final Color? backgroundColor;
  final VoidCallback? onPressed;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.label,
    this.isActive = false,
    this.activeColor,
    this.backgroundColor,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill = backgroundColor ?? (isActive ? (activeColor ?? AppColors.primary) : Colors.white12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: fill,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
