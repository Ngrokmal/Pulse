import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../../domain/entities/friend_alert_sound_entity.dart';
import '../cubit/friend_alert_cubit.dart';

/// Result returned from [showFriendAlertBottomSheet] when the user picks a
/// sound to attach to their next message. `sendImmediately == true` means
/// "Send" was tapped (alert-only or combined with whatever text is already
/// in the composer); `false` means "just select" is not offered in v1 — kept
/// for forward-compatibility with a future "attach, keep composing" mode.
class FriendAlertSelection {
  final AlertAudioMetadata alert;
  const FriendAlertSelection(this.alert);
}

/// Opens the "Friend Alert Sounds" bottom sheet (50–60% of screen height,
/// stays on the chat screen — no navigation away). Returns the selected
/// [AlertAudioMetadata] if the user tapped Send on a sound, else null.
Future<FriendAlertSelection?> showFriendAlertBottomSheet({
  required BuildContext context,
  required String ownerUid,
  required String chatId,
}) {
  return showModalBottomSheet<FriendAlertSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return BlocProvider<FriendAlertCubit>(
        create: (_) => FriendAlertCubit(
          getFriendAlertSoundsUseCase: di.sl(),
          createFriendAlertSoundUseCase: di.sl(),
          renameFriendAlertSoundUseCase: di.sl(),
          replaceFriendAlertSoundUseCase: di.sl(),
          deleteFriendAlertSoundUseCase: di.sl(),
          recordingService: di.sl(),
          previewPlayer: di.sl(),
          firestore: di.sl(),
          ownerUid: ownerUid,
          chatId: chatId,
        )..load(),
        child: const _FriendAlertSheetContent(),
      );
    },
  );
}

class _FriendAlertSheetContent extends StatefulWidget {
  const _FriendAlertSheetContent();

  @override
  State<_FriendAlertSheetContent> createState() => _FriendAlertSheetContentState();
}

class _FriendAlertSheetContentState extends State<_FriendAlertSheetContent> {
  bool _showCreateFlow = false;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.58,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.small),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.medium),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded, color: AppColors.primaryAccent),
                    const SizedBox(width: AppSpacing.small),
                    const Text(
                      'Friend Alert Sounds',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (_showCreateFlow)
                      TextButton(
                        onPressed: () => setState(() => _showCreateFlow = false),
                        child: const Text('Back'),
                      ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              Expanded(
                child: _showCreateFlow
                    ? _CreateSoundFlow(onDone: () => setState(() => _showCreateFlow = false))
                    : _SoundListView(onCreateTap: () => setState(() => _showCreateFlow = true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoundListView extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _SoundListView({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FriendAlertCubit, FriendAlertState>(
      listenWhen: (p, c) => c.errorMessage != null && c.errorMessage != p.errorMessage,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
      },
      builder: (context, state) {
        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryAccent));
        }

        if (state.sounds.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_off_rounded, color: AppColors.textSecondary, size: 40),
                const SizedBox(height: AppSpacing.small),
                const Text('No custom sounds', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.large),
                _PremiumCreateButton(onTap: onCreateTap),
              ],
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
                itemCount: state.sounds.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.small),
                itemBuilder: (context, index) => _SoundTile(sound: state.sounds[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.medium),
              child: SizedBox(width: double.infinity, child: _PremiumCreateButton(onTap: onCreateTap, compact: true)),
            ),
          ],
        );
      },
    );
  }
}

class _PremiumCreateButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  const _PremiumCreateButton({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryAccent]),
        borderRadius: AppRadius.button,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.button,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.large, vertical: compact ? 14 : 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.add_circle_outline_rounded, color: Colors.white),
                SizedBox(width: AppSpacing.small),
                Text('Create Alert Sound', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  final FriendAlertSoundEntity sound;
  const _SoundTile({required this.sound});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FriendAlertCubit>();
    return Container(
      decoration: BoxDecoration(color: AppColors.inputBackground, borderRadius: AppRadius.input),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.small, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primaryAccent),
            onPressed: () => cubit.previewExistingSound(sound),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(sound.displayName,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                Text(
                  sound.isGlobal ? 'Global' : 'This friend only',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
            color: AppColors.surface,
            onSelected: (value) => _handleMenu(context, value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename', style: TextStyle(color: AppColors.textPrimary))),
              PopupMenuItem(value: 'replace', child: Text('Replace', style: TextStyle(color: AppColors.textPrimary))),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
            ],
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            ),
            onPressed: () => Navigator.of(context).pop(FriendAlertSelection(sound.metadata)),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _handleMenu(BuildContext context, String value) {
    final cubit = context.read<FriendAlertCubit>();
    switch (value) {
      case 'rename':
        _promptRename(context, cubit);
        break;
      case 'replace':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: cubit,
              child: Scaffold(
                backgroundColor: AppColors.backgroundBottom,
                appBar: AppBar(title: Text('Replace “${sound.displayName}”')),
                body: _CreateSoundFlow(
                  replaceTarget: sound,
                  onDone: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
        break;
      case 'delete':
        cubit.delete(sound);
        break;
    }
  }

  void _promptRename(BuildContext context, FriendAlertCubit cubit) {
    final controller = TextEditingController(text: sound.displayName);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rename sound', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              cubit.rename(sound, controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Record (1–5s) → Preview → Name → Upload. Used both for "Create New Sound"
/// and, with [replaceTarget] set, for "Replace" (skips the name step).
class _CreateSoundFlow extends StatefulWidget {
  final VoidCallback onDone;
  final FriendAlertSoundEntity? replaceTarget;
  const _CreateSoundFlow({required this.onDone, this.replaceTarget});

  @override
  State<_CreateSoundFlow> createState() => _CreateSoundFlowState();
}

class _CreateSoundFlowState extends State<_CreateSoundFlow> {
  final TextEditingController _nameController = TextEditingController();
  bool _saveAsGlobal = false;

  static const List<String> _suggestions = ['Wake Up', 'Open Chat', 'Emergency', 'Call Me', 'Look Here'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FriendAlertCubit, FriendAlertState>(
      listenWhen: (p, c) => c.errorMessage != null && c.errorMessage != p.errorMessage,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
      },
      builder: (context, state) {
        final cubit = context.read<FriendAlertCubit>();

        if (state.recordingPhase == FriendAlertRecordingPhase.idle) {
          return _RecordStep(onStart: cubit.startRecording);
        }

        if (state.recordingPhase == FriendAlertRecordingPhase.recording) {
          return _RecordingInProgressStep(onStop: cubit.stopRecording);
        }

        // recorded → preview + (name, for create) + save
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.medium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${(state.recordedDurationMs / 1000).toStringAsFixed(1)}s recorded',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.medium),
              Center(
                child: IconButton(
                  iconSize: 56,
                  icon: Icon(
                    state.isPreviewPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                    color: AppColors.primaryAccent,
                  ),
                  onPressed: state.isPreviewPlaying ? cubit.stopPreview : cubit.previewRecordedFile,
                ),
              ),
              const SizedBox(height: AppSpacing.medium),
              if (widget.replaceTarget == null) ...[
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Name this sound',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.small),
                Wrap(
                  spacing: 8,
                  children: _suggestions
                      .map((s) => ActionChip(
                            label: Text(s),
                            onPressed: () => setState(() => _nameController.text = s),
                          ))
                      .toList(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _saveAsGlobal,
                  onChanged: (v) => setState(() => _saveAsGlobal = v),
                  title: const Text('Available for all friends', style: TextStyle(color: AppColors.textPrimary)),
                  activeColor: AppColors.primaryAccent,
                ),
              ],
              const SizedBox(height: AppSpacing.small),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.isBusy ? null : cubit.discardRecording,
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: state.isBusy
                          ? null
                          : () async {
                              if (widget.replaceTarget != null) {
                                await cubit.replaceAudio(widget.replaceTarget!);
                                widget.onDone();
                                return;
                              }
                              if (_nameController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Give this sound a name first.')));
                                return;
                              }
                              final sound = await cubit.saveRecordedAs(
                                displayName: _nameController.text,
                                asGlobal: _saveAsGlobal,
                              );
                              if (sound == null) {
                                // saveRecordedAs already surfaced errorMessage via the
                                // BlocConsumer listener above — just stay on this step.
                                return;
                              }
                              if (context.mounted) {
                                Navigator.of(context).pop(FriendAlertSelection(sound.metadata));
                              }
                            },
                      child: state.isBusy
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(widget.replaceTarget != null ? 'Save' : 'Save & Send'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordStep extends StatelessWidget {
  final VoidCallback onStart;
  const _RecordStep({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Record 1–5 seconds', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.medium),
          GestureDetector(
            onTap: onStart,
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingInProgressStep extends StatelessWidget {
  final VoidCallback onStop;
  const _RecordingInProgressStep({required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Recording…', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.medium),
          GestureDetector(
            onTap: onStop,
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.stop_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          const Text('Max 5 seconds', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
