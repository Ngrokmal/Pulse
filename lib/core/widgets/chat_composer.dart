import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// UI-polish pass (presentation-layer only, Day 6 M3 follow-up): visual-only
/// replacement for the duplicated `TextField` + `IconButton` composer Row in
/// `chat_screen.dart` / `group_chat_screen.dart`. Takes the same controller
/// and callbacks the screens already wired to `TypingStarted/Stopped` and
/// `Send*MessageEvent` — no new state, no new event, nothing added to the
/// send/typing pipeline itself.
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback? onAttachmentTap;
  final Widget? micButton;
  // Friend Alert Sounds (Premium Social Feature) — optional, additive.
  // When null (e.g. GroupChatScreen, which doesn't pass it), layout and
  // behavior are byte-for-byte identical to before this feature existed.
  final Widget? bellWidget;
  // Voice Message recording/draft bar (Bug 2/4/8): when non-null, this
  // entirely replaces the text field + mic/send row — matching WhatsApp,
  // where the composer's text field is hidden while a voice message is
  // being recorded or sits paused as a draft. Everything else about the
  // composer (padding, SafeArea) stays identical.
  final Widget? recordingBar;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSend,
    this.onAttachmentTap,
    this.micButton,
    this.bellWidget,
    this.recordingBar,
  });

  @override
  Widget build(BuildContext context) {
    if (recordingBar != null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.small,
            vertical: AppSpacing.small,
          ),
          child: recordingBar!,
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.small,
          vertical: AppSpacing.small,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onAttachmentTap != null) ...[
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.textSecondary),
                onPressed: onAttachmentTap,
              ),
            ],
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: AppColors.inputBackground,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        hintStyle: TextStyle(color: AppColors.textSecondary),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: onChanged,
                      onSubmitted: (_) => onSend(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  if (bellWidget != null)
                    Positioned(
                      top: -14,
                      right: 4,
                      child: bellWidget!,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            if (micButton == null)
              _SendButton(onSend: onSend)
            else
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  return value.text.trim().isEmpty ? micButton! : _SendButton(onSend: onSend);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onSend;
  const _SendButton({required this.onSend});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.send_rounded, color: Colors.white),
        onPressed: onSend,
      ),
    );
  }
}
