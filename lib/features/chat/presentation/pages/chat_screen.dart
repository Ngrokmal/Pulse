import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/utils/active_chat_tracker.dart';
import '../../../../core/utils/chat_attachment_picker.dart';
import '../../../../core/utils/chat_row_builder.dart';
import '../../../../core/utils/media_cache_manager.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../../core/widgets/chat_composer.dart';
import '../../../../core/widgets/date_separator_label.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../../../core/widgets/file_message_bubble.dart';
import '../../../../core/widgets/image_message_bubble.dart';
import '../../../../core/widgets/media_attachment_sheet.dart';
import '../../../../core/widgets/media_preview_dialog.dart';
import '../../../../core/widgets/alert_sound_playback_button.dart';
import '../../../../core/widgets/message_bubble.dart';
import '../../../../core/widgets/message_status_icon.dart';
import '../../../../core/widgets/mic_record_button.dart';
import '../../../../core/widgets/report_dialog.dart';
import '../../../../core/widgets/scroll_to_bottom_button.dart';
import '../../../../core/widgets/typing_indicator_label.dart';
import '../../../../core/widgets/video_message_bubble.dart';
import '../widgets/chat_app_bar.dart';
import '../../../../core/widgets/voice_message_bubble.dart';
import '../../../../core/widgets/voice_recording_bar.dart';
import '../../../admin/domain/usecases/report_message_usecase.dart';
import '../../../custom_alert/domain/entities/alert_audio_metadata_entity.dart';
import '../../../custom_alert/presentation/widgets/friend_alert_bell.dart';
import '../../../custom_alert/presentation/widgets/friend_alert_bottom_sheet.dart';
import '../../data/services/voice_recording_coordinator.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/entities/message_type.dart';
import '../../domain/entities/voice_draft_entity.dart';
import '../../domain/services/voice_recording_service.dart';
import '../blocs/chat_bloc.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  const ChatScreen({super.key, required this.chatId, required this.currentUserId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  late final ChatBloc _chatBloc;
  late final VoiceRecordingCoordinator _voiceCoordinator;
  bool _isLoadingOlderMessages = false;

  bool _hasAutoScrolledToLatest = false;

  int _lastItemCount = 0;
  bool _showScrollToBottomButton = false;
  static const double _nearBottomThresholdPx = 120;

  final TextEditingController _textController = TextEditingController();
  bool _isTyping = false;
  Timer? _typingTimeout;
  static const _typingTimeoutDuration = Duration(seconds: 3);

  late final String _friendUid = _extractFriendUid(widget.chatId, widget.currentUserId);

  static String _extractFriendUid(String chatId, String currentUserId) {
    final parts = chatId.split('_');
    if (parts.length != 3 || parts[0] != 'direct') return '';
    return parts[1] == currentUserId ? parts[2] : parts[1];
  }

  @override
  void initState() {
    super.initState();
    ActiveChatTracker.instance.setActiveChat(widget.chatId);
    _chatBloc = di.sl<ChatBloc>()
      ..add(LoadMessagesEvent(widget.chatId, currentUserId: widget.currentUserId));
    _voiceCoordinator = di.sl<VoiceRecordingCoordinator>();

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      _evictThisChatMediaFromImageMemory();
    }

    if (_scrollController.position.pixels <= _scrollController.position.minScrollExtent &&
        !_isLoadingOlderMessages) {
      final currentState = _chatBloc.state;
      if (currentState is ChatLoadedState && currentState.messages.isNotEmpty) {
        _isLoadingOlderMessages = true;
        final oldestMessage = currentState.messages.first;
        _chatBloc.add(LoadOlderMessagesEvent(
          chatId: widget.chatId,
          beforeCreatedAt: oldestMessage.createdAt,
        ));
        _chatBloc.stream.first.then((_) {
          if (mounted) _isLoadingOlderMessages = false;
        });
      }
    }

    _refreshScrollToBottomButtonVisibility();
  }

  void _refreshScrollToBottomButtonVisibility() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distanceFromBottom = position.maxScrollExtent - position.pixels;
    final shouldShow = distanceFromBottom > _nearBottomThresholdPx;
    if (shouldShow != _showScrollToBottomButton && mounted) {
      setState(() => _showScrollToBottomButton = shouldShow);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _tryScrollToLatest([int attempt = 0]) {
    if (!mounted) return;
    if (!_scrollController.hasClients || _scrollController.position.maxScrollExtent <= 0) {
      if (attempt >= 5) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryScrollToLatest(attempt + 1));
      return;
    }
    _scrollToBottom(animate: false);
  }

  void _onComposerChanged(String text) {
    _typingTimeout?.cancel();
    if (text.trim().isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        _chatBloc.add(TypingStoppedEvent(chatId: widget.chatId, uid: widget.currentUserId));
      }
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      _chatBloc.add(TypingStartedEvent(chatId: widget.chatId, uid: widget.currentUserId));
    }
    _typingTimeout = Timer(_typingTimeoutDuration, () {
      _isTyping = false;
      _chatBloc.add(TypingStoppedEvent(chatId: widget.chatId, uid: widget.currentUserId));
    });
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _typingTimeout?.cancel();
    _isTyping = false;
    _chatBloc.add(SendMessageEvent(
      chatId: widget.chatId,
      senderId: widget.currentUserId,
      text: text,
    ));
    _textController.clear();
  }

  Future<void> _openAttachmentMenu() async {
    final option = await MediaAttachmentSheet.show(context);
    if (option == null || !mounted) return;

    switch (option) {
      case AttachmentOption.galleryImage:
        await _pickAndSendImage(fromCamera: false);
        break;
      case AttachmentOption.cameraImage:
        await _pickAndSendImage(fromCamera: true);
        break;
      case AttachmentOption.video:
        await _pickAndSendVideo();
        break;
      case AttachmentOption.file:
        await _pickAndSendFile();
        break;
    }
  }

  Future<void> _pickAndSendImage({required bool fromCamera}) async {
    final attachment = await ChatAttachmentPicker.pickImage(fromCamera: fromCamera);
    if (attachment == null || !mounted) return;
    final result = await MediaPreviewDialog.show(context, file: attachment.file);
    if (result == null) return;
    _chatBloc.add(SendMediaMessageEvent(
      chatId: widget.chatId,
      senderId: widget.currentUserId,
      type: MessageType.image,
      file: attachment.file,
      fileName: attachment.fileName,
      fileSizeBytes: attachment.fileSizeBytes,
      mimeType: attachment.mimeType,
      caption: result.caption,
    ));
  }

  Future<void> _pickAndSendVideo() async {
    final attachment = await ChatAttachmentPicker.pickVideo(fromCamera: false);
    if (attachment == null || !mounted) return;
    final result = await MediaPreviewDialog.show(context, file: attachment.file, isVideo: true);
    if (result == null) return;
    _chatBloc.add(SendMediaMessageEvent(
      chatId: widget.chatId,
      senderId: widget.currentUserId,
      type: MessageType.video,
      file: attachment.file,
      fileName: attachment.fileName,
      fileSizeBytes: attachment.fileSizeBytes,
      mimeType: attachment.mimeType,
      caption: result.caption,
    ));
  }

  Future<void> _pickAndSendFile() async {
    final attachment = await ChatAttachmentPicker.pickGenericFile();
    if (attachment == null || !mounted) return;
    _chatBloc.add(SendMediaMessageEvent(
      chatId: widget.chatId,
      senderId: widget.currentUserId,
      type: MessageType.file,
      file: attachment.file,
      fileName: attachment.fileName,
      fileSizeBytes: attachment.fileSizeBytes,
      mimeType: attachment.mimeType,
    ));
  }

  Future<void> _startVoiceRecording() async {
    try {
      await _voiceCoordinator.startRecording(widget.chatId, widget.currentUserId);
    } catch (e) {
      _onVoiceRecordingError(e.toString());
    }
  }

  void _onVoiceDraftSent(File file, Duration duration, List<double> waveform) {
    if (!mounted || duration.inMilliseconds <= 0) return;
    final fileSizeBytes = file.existsSync() ? file.lengthSync() : 0;
    _chatBloc.add(SendMediaMessageEvent(
      chatId: widget.chatId,
      senderId: widget.currentUserId,
      type: MessageType.voice,
      file: file,
      fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      fileSizeBytes: fileSizeBytes,
      mimeType: 'audio/m4a',
      durationMs: duration.inMilliseconds,
      waveform: waveform,
    ));
  }

  void _onVoiceRecordingError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFriendAlertSheet() async {
    final selection = await showFriendAlertBottomSheet(
      context: context,
      ownerUid: widget.currentUserId,
      chatId: widget.chatId,
    );
    if (selection == null || !mounted) return;

    final AlertAudioMetadata alert = selection.alert;
    final text = selection.messageText.trim().isNotEmpty
        ? selection.messageText.trim()
        : _textController.text.trim();

    _typingTimeout?.cancel();
    _isTyping = false;
    _chatBloc.add(SendMessageWithAlertEvent(
      chatId: widget.chatId,
      senderId: widget.currentUserId,
      text: text,
      alert: alert,
    ));
    _textController.clear();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    _voiceCoordinator.pauseRecording();

    _typingTimeout?.cancel();
    if (_isTyping) {
      _chatBloc.add(TypingStoppedEvent(chatId: widget.chatId, uid: widget.currentUserId));
    }
    _textController.dispose();

    ActiveChatTracker.instance.clearActiveChat();
    _evictThisChatMediaFromImageMemory();
    _chatBloc.close();
    super.dispose();
  }

  void _evictThisChatMediaFromImageMemory() {
    final state = _chatBloc.state;
    if (state is! ChatLoadedState) return;
    final urls = <String?>[];
    for (final message in state.messages) {
      urls.add(message.mediaUrl);
      urls.add(message.thumbnailUrl);
    }
    MediaCacheManager.instance.evictImageUrls(urls);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatBloc>.value(
      value: _chatBloc,
      child: Scaffold(
        appBar: ChatAppBar(friendUid: _friendUid, currentUserId: widget.currentUserId),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  BlocListener<ChatBloc, ChatState>(
                    listener: (context, state) {
                      if (state is! ChatLoadedState) return;
                      final currentCount = state.messages.length + state.pendingUploads.length;

                      if (!_hasAutoScrolledToLatest) {
                        if (state.messages.isEmpty && state.pendingUploads.isEmpty) return;
                        _hasAutoScrolledToLatest = true;
                        _lastItemCount = currentCount;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _tryScrollToLatest();
                        });
                        return;
                      }

                      if (currentCount > _lastItemCount) {
                        final isOwnMessage = state.messages.isNotEmpty &&
                            state.messages.last.senderId == widget.currentUserId;
                        final wasNearBottom = !_showScrollToBottomButton;
                        if (isOwnMessage || wasNearBottom) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _scrollToBottom();
                          });
                        } else {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _refreshScrollToBottomButtonVisibility();
                          });
                        }
                      }
                      _lastItemCount = currentCount;
                    },
                    child: BlocBuilder<ChatBloc, ChatState>(
                      builder: (context, state) {
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _buildBody(state),
                        );
                      },
                    ),
                  ),
                  if (_showScrollToBottomButton)
                    ScrollToBottomButton(onTap: () => _scrollToBottom()),
                ],
              ),
            ),
            BlocBuilder<ChatBloc, ChatState>(
              builder: (context, state) {
                final isTyping = state is ChatLoadedState && state.typingUserIds.isNotEmpty;
                return TypingIndicatorLabel(label: isTyping ? 'টাইপ করছেন…' : null);
              },
            ),
            ValueListenableBuilder<VoiceDraftEntity?>(
              valueListenable: _voiceCoordinator.draftStore.draftNotifier,
              builder: (context, draft, _) {
                final showRecordingBar = draft != null && draft.chatId == widget.chatId && draft.userId == widget.currentUserId;
                return ChatComposer(
                  controller: _textController,
                  onChanged: _onComposerChanged,
                  onSend: _sendMessage,
                  onAttachmentTap: _openAttachmentMenu,
                  bellWidget: FriendAlertBell(
                    isComposerActive: _isTyping,
                    onTap: _openFriendAlertSheet,
                  ),
                  micButton: MicRecordButton(onTap: _startVoiceRecording),
                  recordingBar: showRecordingBar
                      ? VoiceRecordingBar(
                          chatId: widget.chatId,
                          userId: widget.currentUserId,
                          coordinator: _voiceCoordinator,
                          onSend: _onVoiceDraftSent,
                          onError: _onVoiceRecordingError,
                        )
                      : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatState state) {
    if (state is ChatLoading) {
      return const Center(
        key: ValueKey('chat-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (state is ChatLoadedState) {
      if (state.messages.isEmpty && state.pendingUploads.isEmpty) {
        return const EmptyState(
          key: ValueKey('chat-empty'),
          icon: Icons.chat_bubble_outline,
          title: 'No messages yet',
          subtitle: 'Say hello to start the conversation',
        );
      }

      final rows = buildChatRowsWithDateSeparators<MessageEntity>(
        state.messages,
        (m) => m.createdAt,
      );
      if (rows.isEmpty && state.pendingUploads.isNotEmpty) {
        rows.add(ChatRow<MessageEntity>.separator(DateTime.now()));
      }
      final pendingStartIndex = rows.length;
      final totalCount = pendingStartIndex + state.pendingUploads.length;

      return ListView.builder(
        key: const ValueKey('chat-loaded'),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (index < pendingStartIndex) {
            final row = rows[index];
            if (row.isSeparator) {
              return DateSeparatorLabel(
                key: ValueKey('date-${row.separatorDate!.toIso8601String()}'),
                label: formatDateSeparator(row.separatorDate!),
              );
            }
            final message = row.message!;
            final isMe = message.senderId == widget.currentUserId;
            final bubble = MessageBubble(
              text: message.text,
              isMe: isMe,
              timeLabel: formatMessageBubbleTime(message.createdAt),
              statusIcon: isMe ? MessageStatusIcon(status: message.status) : null,
              mediaContent: message.hasAlert
                  ? AlertSoundPlaybackButton(
                      audioUrl: message.alertAudioUrl!,
                      displayName: message.alertDisplayName ?? 'Alert',
                      autoPlayOnce: false,
                      playbackControllerFactory: () => di.sl<VoicePlaybackController>(),
                    )
                  : _buildMediaContent(message, isMe),
            );
            if (isMe) return KeyedSubtree(key: ValueKey(message.messageId), child: bubble);
            return GestureDetector(
              key: ValueKey(message.messageId),
              onLongPress: () => _reportMessage(message),
              child: bubble,
            );
          }

          final pending = state.pendingUploads[index - pendingStartIndex];
          return MessageBubble(
            key: ValueKey(pending.localId),
            text: pending.caption,
            isMe: true,
            timeLabel: '',
            mediaContent: _buildPendingContent(pending),
          );
        },
      );
    }
    if (state is ChatErrorState) {
      return ErrorStateView(key: const ValueKey('chat-error'), message: state.message);
    }
    return const EmptyState(
      key: ValueKey('chat-initial'),
      icon: Icons.chat_bubble_outline,
      title: 'No Messages',
    );
  }

  Future<void> _reportMessage(MessageEntity message) async {
    final submission = await showReportDialog(context, title: 'Report Message');
    if (submission == null) return;
    final result = await di.sl<ReportMessageUseCase>()(
      reporterUid: widget.currentUserId,
      messageId: message.messageId,
      chatId: widget.chatId,
      reason: submission.reason,
    );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted'))),
    );
  }

  Widget? _buildMediaContent(MessageEntity message, bool isMe) {
    switch (message.type) {
      case MessageType.image:
        return ImageMessageBubble(imageUrl: message.mediaUrl);
      case MessageType.video:
        return VideoMessageBubble(
          thumbnailUrl: message.thumbnailUrl,
          durationMs: message.durationMs,
        );
      case MessageType.file:
        return FileMessageBubble(
          fileName: message.fileName ?? 'File',
          fileSizeBytes: message.fileSizeBytes,
          mediaUrl: message.mediaUrl,
        );
      case MessageType.voice:
        return VoiceMessageBubble(
          durationMs: message.durationMs ?? 0,
          waveform: message.waveform ?? const [],
          isMine: isMe,
          mediaUrl: message.mediaUrl,
          playbackControllerFactory: () => di.sl<VoicePlaybackController>(),
        );
      default:
        return null;
    }
  }

  Widget _buildPendingContent(PendingMediaUpload pending) {
    final failed = pending.stage == MediaUploadStage.failed;
    void retry() => _chatBloc.add(RetryMediaUploadEvent(pending.localId));
    void cancel() => _chatBloc.add(CancelMediaUploadEvent(pending.localId));

    switch (pending.type) {
      case MessageType.image:
        return ImageMessageBubble(
          localFile: pending.file,
          progress: pending.progress,
          failed: failed,
          onRetry: retry,
          onCancel: cancel,
        );
      case MessageType.video:
        return VideoMessageBubble(
          localFile: pending.file,
          durationMs: pending.durationMs,
          progress: pending.progress,
          failed: failed,
          onRetry: retry,
          onCancel: cancel,
        );
      default:
        return FileMessageBubble(
          fileName: pending.fileName,
          fileSizeBytes: pending.fileSizeBytes,
          progress: pending.progress,
          failed: failed,
          onRetry: retry,
          onCancel: cancel,
        );
    }
  }
}