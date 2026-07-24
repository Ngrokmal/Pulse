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

  // BUG FIX (chat opens at oldest message instead of latest): messages are
  // sorted ascending (ChatBloc._sortedMessages) and the ListView.builder
  // below is not reversed, so with no explicit scroll call the list simply
  // sits at its default offset 0 — the oldest message. This flag makes the
  // one-time "jump to latest on open" fire only for the *first* loaded
  // snapshot for this screen instance, so it never fights the user's manual
  // scroll-up (e.g. while they're reading older history and a new message
  // arrives), and never interferes with the existing top-of-list
  // "load older messages" pagination in _onScroll.
  bool _hasAutoScrolledToLatest = false;

  // BUG-2 (auto-scroll on new messages): tracks the total item count
  // (messages + pending uploads) as of the last processed state, so the
  // BlocListener below can detect "a new item was appended" without
  // depending on any specific event type. _showScrollToBottomButton mirrors
  // whether the user is currently scrolled away from the bottom — computed
  // from scroll position in _onScroll, and re-checked after new content
  // changes maxScrollExtent (see the BlocListener below), since adding
  // items to the end of the list does not itself fire a scroll notification.
  int _lastItemCount = 0;
  bool _showScrollToBottomButton = false;
  static const double _nearBottomThresholdPx = 120;

  // Day 6 Milestone 1 (Typing Indicator fix): GroupChatScreen-এর composer
  // প্যাটার্নের হুবহু 1:1-সমতুল্য — পূর্বে এই স্ক্রিনে কোনো TextField ছিল না
  // (handoff.md ধারা ৬-এ চিহ্নিত pre-existing gap), তাই bloc/repository/usecase
  // লেয়ারের বিদ্যমান Typing Indicator লজিক (SendMessageEvent/TypingStartedEvent/
  // TypingStoppedEvent, আগে থেকেই সম্পূর্ণ ও symmetric) reuse করে এখানে trigger-side
  // যোগ করা হলো — নতুন কোনো bloc/usecase/repository/schema তৈরি হয়নি।
  final TextEditingController _textController = TextEditingController();
  bool _isTyping = false;
  Timer? _typingTimeout;
  static const _typingTimeoutDuration = Duration(seconds: 3);

  // Task 1 (WhatsApp-style header): ChatScreen only ever receives chatId +
  // currentUserId (no separate friendUid param, and adding one would mean
  // touching every call site — home_screen.dart, friend/non_friend profile
  // screens, fcm_message_handler.dart). Direct-chat ids are always
  // generated as `direct_<uidA>_<uidB>` (sorted) by
  // ChatRepositoryImpl.generateDirectChatId, so the friend's uid can be
  // derived purely client-side with zero extra Firestore reads.
  late final String _friendUid = _extractFriendUid(widget.chatId, widget.currentUserId);

  static String _extractFriendUid(String chatId, String currentUserId) {
    final parts = chatId.split('_');
    if (parts.length != 3 || parts[0] != 'direct') return '';
    return parts[1] == currentUserId ? parts[2] : parts[1];
  }

  @override
  void initState() {
    super.initState();
    // রুল ৪ ও বাগ ৫: স্ক্রিন ট্র্যাকিং ইনিশিয়েশন ও স্টেট বাইন্ডিং
    ActiveChatTracker.instance.setActiveChat(widget.chatId);
    _chatBloc = di.sl<ChatBloc>()
      ..add(LoadMessagesEvent(widget.chatId, currentUserId: widget.currentUserId));
    _voiceCoordinator = di.sl<VoiceRecordingCoordinator>();

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // বাগ ৮ ফিক্স: চ্যাট স্ক্রিন অতিরিক্ত স্ক্রোলিং করার সময় মেমোরি অপ্টিমাইজেশন
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      MediaCacheManager.instance.forceFlushImageMemory();
    }

    // Phase 3.3: তালিকার শুরুতে পৌঁছালে পুরনো মেসেজ পেজিনেশন ট্রিগার করা
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
        // পরবর্তী state emit-এর পর ফ্ল্যাগ রিসেট, যাতে ধারাবাহিক ট্রিগার আটকানো যায়
        _chatBloc.stream.first.then((_) {
          if (mounted) _isLoadingOlderMessages = false;
        });
      }
    }

    _refreshScrollToBottomButtonVisibility();
  }

  // BUG-2: recomputes whether the "scroll to bottom" button should be
  // visible, based on distance from the bottom of the list. Called both on
  // real user scroll (_onScroll) and after new content is appended (see
  // BlocListener in build()), since appending items changes maxScrollExtent
  // without necessarily firing a scroll notification.
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

  // Day 6 Milestone 1: TextField.onChanged থেকে প্রতি keystroke-এ কল হয় —
  // GroupChatScreen._onComposerChanged-এর হুবহু সমতুল্য (not-typing→typing
  // ট্রানজিশনে একবার TypingStartedEvent, ৩-সেকেন্ড ইনঅ্যাক্টিভিটিতে
  // TypingStoppedEvent, টেক্সট খালি হলে অবিলম্বে stop)।
  // TYPING INDICATOR DISABLED: this used to dispatch TypingStartedEvent/
  // TypingStoppedEvent on every keystroke via a 3s inactivity Timer. Body is
  // now a no-op — still wired to TextField.onChanged (see build() below) so
  // no call-site changes are needed elsewhere, but nothing fires anymore.
  void _onComposerChanged(String text) {}

  // Day 6 Milestone 1: GroupChatScreen._sendMessage-এর সমতুল্য — শুধু পার্থক্য
  // messageId এখন caller-supplied নয়, SendMessageUseCase internally
  // generateMessageId দিয়ে জেনারেট করে (SendGroupMessageEvent-এর সাথে
  // সামঞ্জস্যপূর্ণ, দেখুন chat_bloc.dart/send_message_usecase.dart)।
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

  // Friend Alert Sounds (Premium Social Feature): opens the bottom sheet
  // (stays on this screen, does not navigate away). If the user taps Send
  // on a sound, dispatches SendMessageWithAlertEvent — combining whatever
  // text is currently in the composer (Message+Alert mode) or empty
  // (Alert-only mode), matching the three send modes in the spec.
  Future<void> _openFriendAlertSheet() async {
    final selection = await showFriendAlertBottomSheet(
      context: context,
      ownerUid: widget.currentUserId,
      chatId: widget.chatId,
    );
    if (selection == null || !mounted) return;

    final AlertAudioMetadata alert = selection.alert;
    final text = _textController.text.trim();

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
    // রুল ৪ ও বাগ ৮: স্ট্রিম ও মেমোরি ক্লিনআপ লাইফসাইকেল ট্র্যাকিং ম্যান্ডেটরি
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    // Voice Message audit (Bug 3): leaving this chat screen (user opens
    // another page inside the app) must not drop an in-progress recording —
    // auto-pause it into a draft instead. Fire-and-forget: dispose() can't
    // be async, and VoiceRecordingCoordinator/VoiceDraftStore are app-wide
    // singletons so this completes safely even after this State is gone.
    // No-op if nothing is actively recording, or if any active recording
    // belongs to a different feature (see VoiceRecordingCoordinator's doc
    // comment on FriendAlertCubit sharing the same underlying service).
    _voiceCoordinator.pauseRecording();

    // Day 6 Milestone 1: স্ক্রিন বন্ধ হওয়ার আগে টাইপিং চলছিল থাকলে বন্ধ —
    // GroupChatScreen.dispose()-এর সমতুল্য (ChatBloc.close()-এও একই cleanup
    // আছে, double-safety, idempotent arrayRemove তাই ক্ষতি নেই)।
    _typingTimeout?.cancel();
    if (_isTyping) {
      _chatBloc.add(TypingStoppedEvent(chatId: widget.chatId, uid: widget.currentUserId));
    }
    _textController.dispose();

    ActiveChatTracker.instance.clearActiveChat();
    MediaCacheManager.instance.forceFlushImageMemory(); // মেমোরি লিক লকড ফিক্স
    _chatBloc.close(); // ব্লক ও এর রিপোজিটরি স্ট্রিম সাবস্ক্রিপশন ক্লিনআপ
    super.dispose();
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
                        // Scheduled for the next frame so the ListView has
                        // already laid out this snapshot's items (maxScrollExtent
                        // is 0/stale otherwise). Ascending sort + non-reversed
                        // ListView means "latest message" = bottom = maxScrollExtent.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _scrollToBottom(animate: false);
                        });
                        return;
                      }

                      // BUG-2: auto-scroll only when (a) the new item is our
                      // own just-sent message — WhatsApp always shows you your
                      // own send — or (b) the user was already near the
                      // bottom when it arrived. Otherwise leave their scroll
                      // position alone and just make sure the "scroll to
                      // bottom" button reflects the now-larger scroll extent.
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
            // TYPING INDICATOR DISABLED: label removed entirely (was rendered
            // here based on ChatLoadedState.typingUserIds, which the bloc no
            // longer populates — see chat_bloc.dart).
            // Day 6 Milestone 1 (composer fix): এই স্ক্রিনে আগে কোনো
            // TextField/composer ছিল না (handoff.md ধারা ৬) — GroupChatScreen-এর
            // composer Row-এর হুবহু 1:1-সমতুল্য যোগ করা হলো। UI-polish pass:
            // এখন শেয়ার্ড ChatComposer widget ব্যবহার করে (একই controller/
            // callback, শুধু styling)।
            //
            // Voice Message audit (Bug 2/4/8): ValueListenableBuilder on the
            // draft store decides whether this shows the normal text
            // composer or the WhatsApp-style recording/draft bar — reactive
            // to VoiceRecordingCoordinator, which is what actually owns the
            // record/pause/resume/delete/send state (survives this widget
            // being rebuilt).
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

  // UI-polish pass: state → widget mapping বের করা হলো যাতে AnimatedSwitcher
  // clean ভাবে transition করতে পারে (প্রতিটি branch-এর একটি ValueKey লাগে)।
  // কোনো bloc/state টাইপ/ফিল্ড এখানে বদলায়নি, শুধু কোন widget আঁকা হবে সেটা।
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

      // BUG-3 (date separators): messages are merged into a row list here
      // (real messages -> ChatRow.message, one ChatRow.separator inserted
      // before the first message of each new calendar day) so the
      // ListView.builder can render both row kinds from a single itemCount/
      // itemBuilder without changing ChatBloc's message ordering/streaming.
      final rows = buildChatRowsWithDateSeparators<MessageEntity>(
        state.messages,
        (m) => m.createdAt,
      );
      // Edge case: a brand-new chat whose very first item is a media upload
      // still in flight (no real messages yet) — still needs a "Today"
      // separator above it, since buildChatRowsWithDateSeparators only saw
      // an empty message list.
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
                      autoPlayOnce: !isMe,
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