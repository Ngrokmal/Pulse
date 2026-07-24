import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// WhatsApp-style floating "jump to latest message" button. Shown by
/// ChatScreen/GroupChatScreen once the user has scrolled away from the
/// bottom of the thread, so that arriving messages don't yank the user's
/// scroll position while they're reading older history (see BUG-2:
/// auto-scroll only fires when the user is already near the bottom, or when
/// they send a message themselves — otherwise this button is the way back
/// down).
class ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  const ScrollToBottomButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
