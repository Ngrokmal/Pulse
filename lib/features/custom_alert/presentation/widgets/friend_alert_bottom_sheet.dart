import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/voice_waveform_view.dart';
import '../../../chat/domain/services/voice_recording_service.dart';
import '../../domain/entities/alert_audio_metadata_entity.dart';
import '../cubit/friend_alert_cubit.dart';

class FriendAlertSelection {
  final AlertAudioMetadata alert;
  final String messageText;
  const FriendAlertSelection(this.alert, {this.messageText = ''});
}

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
          watchFriendAlertSoundsUseCase: di.sl(),
          createFriendAlertSoundUseCase: di.sl(),
          renameFriendAlertSoundUseCase: di.sl(),
          replaceFriendAlertSoundUseCase: di.sl(),
          deleteFriendAlertSoundUseCase: di.sl(),
          recordingService: di.sl(),
          previewPlayer: di.sl(),
          supabase: di.sl(),
          chatLocalDataSource: di.sl(),
          ownerUid: ownerUid,
          chatId: chatId,
        )..load(),
        child: const _FriendAlertSheetContent(),
      );
    },
  );
}

class _FriendAlertSheetContent extends StatelessWidget {
  const _FriendAlertSheetContent();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FriendAlertCubit>();
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(cubit.cancelRecordingIfAny());
      },
      child: Material(
        color: Theme.of(context).canvasColor,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Container(
                color: AppColors.surface,
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
                          const Expanded(
                            child: Text(
                              'Friend Alert',
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                            onPressed: () async {
                              await cubit.cancelRecordingIfAny();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    const Expanded(child: _RecordAlertFlow()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordAlertFlow extends StatefulWidget {
  const _RecordAlertFlow();

  @override
  State<_RecordAlertFlow> createState() => _RecordAlertFlowState();
}

class _RecordAlertFlowState extends State<_RecordAlertFlow> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
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
          if (_messageController.text.isNotEmpty && state.notificationText.isEmpty) {
            _messageController.clear();
          }
          return _RecordStep(onStart: cubit.startRecording);
        }

        if (state.recordingPhase == FriendAlertRecordingPhase.recording ||
            state.recordingPhase == FriendAlertRecordingPhase.paused) {
          return _RecordingInProgressStep(
            isPaused: state.recordingPhase == FriendAlertRecordingPhase.paused,
            recordingService: cubit.recordingService,
            onPause: cubit.pauseRecording,
            onResume: cubit.resumeRecording,
            onStop: cubit.stopRecording,
          );
        }

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
              TextField(
                controller: _messageController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Notification message',
                  hintText: 'e.g. "Wake up, your class starts in 10 minutes."',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                ),
                onChanged: cubit.setNotificationText,
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                'Title: ${state.autoTitle}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.small),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.isBusy
                          ? null
                          : () {
                              cubit.discardRecording();
                              _messageController.clear();
                            },
                      child: const Text('Delete'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.small),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: state.isBusy
                          ? null
                          : () async {
                              final sound = await cubit.send();
                              if (sound == null) {
                                return;
                              }
                              _messageController.clear();
                              if (context.mounted) {
                                Navigator.of(context).pop(
                                  FriendAlertSelection(sound.metadata, messageText: state.notificationText),
                                );
                              }
                            },
                      child: state.isBusy
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Send'),
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
          const Text('Record 1–20 seconds', style: TextStyle(color: AppColors.textSecondary)),
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

class _RecordingInProgressStep extends StatefulWidget {
  final bool isPaused;
  final VoiceRecordingService recordingService;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  const _RecordingInProgressStep({
    required this.isPaused,
    required this.recordingService,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  @override
  State<_RecordingInProgressStep> createState() => _RecordingInProgressStepState();
}

class _RecordingInProgressStepState extends State<_RecordingInProgressStep> {
  Timer? _ticker;
  int _displayMs = 0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _RecordingInProgressStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPaused != widget.isPaused) _syncTicker();
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    setState(() => _displayMs = widget.recordingService.elapsedMs);
    if (widget.isPaused) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _displayMs = widget.recordingService.elapsedMs);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final totalSeconds = (_displayMs / 1000).floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.isPaused ? 'Paused' : 'Recording…',
            style: TextStyle(
              color: widget.isPaused ? AppColors.textSecondary : AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.small),
          Text(_timeLabel, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.medium),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.large),
            child: VoiceWaveformView(
              isLive: !widget.isPaused,
              height: 32,
              liveAmplitudeStream: widget.isPaused ? null : widget.recordingService.amplitudeStream,
            ),
          ),
          const SizedBox(height: AppSpacing.medium),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: widget.isPaused ? widget.onResume : widget.onPause,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: AppColors.inputBackground, shape: BoxShape.circle),
                  child: Icon(
                    widget.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: AppColors.textPrimary,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.medium),
              GestureDetector(
                onTap: widget.onStop,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.stop_rounded, color: Colors.white, size: 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.small),
          const Text('Max 20 seconds', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
