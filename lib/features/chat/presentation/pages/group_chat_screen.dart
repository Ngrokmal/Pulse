import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/utils/active_chat_tracker.dart';
import '../../../../core/utils/chat_row_builder.dart';
import '../../../../core/utils/media_cache_manager.dart';
import '../../../../core/utils/profile_image_cache.dart';
import '../../../../core/utils/time_formatter.dart';
import '../../../../core/widgets/chat_composer.dart';
import '../../../../core/widgets/date_separator_label.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../../../core/widgets/message_bubble.dart';
import '../../../../core/widgets/message_status_icon.dart';
import '../../../../core/widgets/report_dialog.dart';
import '../../../../core/widgets/scroll_to_bottom_button.dart';
import '../../../admin/domain/usecases/report_message_usecase.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/usecases/stream_group_usecase.dart';
import '../blocs/group_chat_bloc.dart';
import 'group_info_screen.dart';

/// GROUP_CHAT_ALGORITHM.md ধারা ১-২ — Milestone 2 (Send + Stream)।
/// pagination, receipt count, permission-gating এই মাইলস্টোনের স্কোপে নেই (পরিকল্পিত,
/// পরবর্তী মাইলস্টোন)। lifecycle-management ChatScreen-এর প্যাটার্নের সাথে সামঞ্জস্যপূর্ণ
/// (ActiveChatTracker/MediaCacheManager একই singleton — ChatScreen অপরিবর্তিত রাখা হয়েছে)।
class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String currentUserId;
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.currentUserId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late final GroupChatBloc _groupChatBloc;
  final TextEditingController _textController = TextEditingController();

  // BUG-2 (group chat opened at oldest message / no auto-scroll): this
  // screen previously had no ScrollController at all. Added following the
  // same pattern already used in ChatScreen — one-time jump to the latest
  // message on open, then auto-scroll only for our own sends or when the
  // user is already near the bottom, with a scroll-to-bottom button
  // otherwise.
  final ScrollController _scrollController = ScrollController();
  bool _hasAutoScrolledToLatest = false;
  int _lastMessageCount = 0;
  bool _showScrollToBottomButton = false;
  static const double _nearBottomThresholdPx = 120;

  // Day 5 Milestone 1: শুধু AppBar-এ group name/photo দেখানোর জন্য — GroupChatBloc
  // messages-এর বাইরে কোনো group-metadata বহন করে না (স্কোপ অপরিবর্তিত রাখতে),
  // তাই বিদ্যমান StreamGroupUseCase (GroupInfoBloc-এও ব্যবহৃত) সরাসরি এখানে
  // reuse করা হলো — কোনো নতুন repository/usecase/DI wiring লাগেনি।
  late final Stream<GroupEntity> _groupStream;

  // Day 6 Milestone 1 (Typing Indicator): _isTyping ফ্ল্যাগ দিয়ে প্রতি
  // keystroke-এ redundant TypingStartedEvent (এবং তাই redundant Firestore
  // write) আটকানো হয় — শুধু not-typing → typing ট্রানজিশনে একবার fire হয়
  // (Minimize Firestore writes)। _typingTimeout প্রতি keystroke-এ reset হয়ে
  // ৩ সেকেন্ড নিষ্ক্রিয়তার পর স্বয়ংক্রিয়ভাবে stop dispatch করে।
  bool _isTyping = false;
  Timer? _typingTimeout;
  static const _typingTimeoutDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    ActiveChatTracker.instance.setActiveChat(widget.groupId);
    _groupStream = di.sl<StreamGroupUseCase>()(widget.groupId);
    _groupChatBloc = di.sl<GroupChatBloc>()
      ..add(LoadGroupMessagesEvent(widget.groupId, currentUserId: widget.currentUserId));
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
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

  @override
  void dispose() {
    _typingTimeout?.cancel();
    // TYPING INDICATOR DISABLED: cleanup dispatch removed — GroupChatBloc no
    // longer acts on this event anyway (no-op handler), but removed here too
    // for clarity.
    // if (_isTyping) {
    //   _groupChatBloc.add(GroupTypingStoppedEvent(groupId: widget.groupId, uid: widget.currentUserId));
    // }
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    ActiveChatTracker.instance.clearActiveChat();
    MediaCacheManager.instance.forceFlushImageMemory();
    _groupChatBloc.close();
    super.dispose();
  }

  // TYPING INDICATOR DISABLED: this used to dispatch GroupTypingStartedEvent/
  // GroupTypingStoppedEvent on every keystroke via a 3s inactivity Timer.
  // Body is now a no-op — still wired to TextField.onChanged so no call-site
  // changes needed elsewhere, but nothing fires anymore.
  void _onComposerChanged(String text) {}

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _typingTimeout?.cancel();
    _isTyping = false;
    _groupChatBloc.add(SendGroupMessageEvent(
      groupId: widget.groupId,
      senderId: widget.currentUserId,
      text: text,
    ));
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GroupChatBloc>.value(
      value: _groupChatBloc,
      child: Scaffold(
        appBar: AppBar(
          title: StreamBuilder<GroupEntity>(
            stream: _groupStream,
            builder: (context, snapshot) {
              final group = snapshot.data;
              final hasPhoto = group?.groupPhotoUrl != null && group!.groupPhotoUrl!.isNotEmpty;
              return Row(
                children: [
                  // UI-polish pass: Hero tag matches the avatar tag used on
                  // HomeScreen's chat-list tile for the same chatId, so
                  // tapping into this screen morphs the avatar into place
                  // instead of popping in abruptly.
                  Hero(
                    tag: 'chat-avatar-${widget.groupId}',
                    child: CircleAvatar(
                      radius: 16,
                      backgroundImage: hasPhoto ? ProfileImageCache.instance.providerFor(group!.groupPhotoUrl!) : null,
                      child: hasPhoto ? null : const Icon(Icons.group, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group?.name ?? 'Group Chat',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Group Info',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupInfoScreen(
                      groupId: widget.groupId,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  BlocListener<GroupChatBloc, GroupChatState>(
                    listener: (context, state) {
                      if (state is! GroupChatLoadedState) return;
                      final currentCount = state.messages.length;

                      if (!_hasAutoScrolledToLatest) {
                        if (state.messages.isEmpty) return;
                        _hasAutoScrolledToLatest = true;
                        _lastMessageCount = currentCount;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _scrollToBottom(animate: false);
                        });
                        return;
                      }

                      // BUG-2: same rule as ChatScreen — auto-scroll for our
                      // own sends or when already near the bottom; otherwise
                      // leave the user's scroll position alone and just
                      // refresh the scroll-to-bottom button's visibility.
                      if (currentCount > _lastMessageCount) {
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
                      _lastMessageCount = currentCount;
                    },
                    child: BlocBuilder<GroupChatBloc, GroupChatState>(
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
            // TYPING INDICATOR DISABLED: label removed entirely.
            ChatComposer(
              controller: _textController,
              onChanged: _onComposerChanged,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  // UI-polish pass: ChatScreen._buildBody-এর group-সমতুল্য — একই কারণে
  // (AnimatedSwitcher-এর জন্য ValueKey সহ widget branches)। কোনো bloc/state
  // ফিল্ড/লজিক বদলায়নি।
  Future<void> _reportMessage(String messageId) async {
    final submission = await showReportDialog(context, title: 'Report Message');
    if (submission == null) return;
    final result = await di.sl<ReportMessageUseCase>()(
      reporterUid: widget.currentUserId,
      messageId: messageId,
      chatId: widget.groupId,
      reason: submission.reason,
    );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted'))),
    );
  }

  Widget _buildBody(GroupChatState state) {
    if (state is GroupChatLoading) {
      return const Center(
        key: ValueKey('group-chat-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (state is GroupChatLoadedState) {
      if (state.messages.isEmpty) {
        return const EmptyState(
          key: ValueKey('group-chat-empty'),
          icon: Icons.forum_outlined,
          title: 'No messages yet',
          subtitle: 'Be the first to say something',
        );
      }
      // BUG-3 (date separators): same row-merging helper ChatScreen uses —
      // see lib/core/utils/chat_row_builder.dart — so the day-boundary rules
      // can't drift between 1:1 and group chat.
      final rows = buildChatRowsWithDateSeparators<MessageEntity>(
        state.messages,
        (m) => m.createdAt,
      );
      return ListView.builder(
        key: const ValueKey('group-chat-loaded'),
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) {
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
            senderLabel: isMe ? null : message.senderId,
            statusIcon: isMe ? MessageStatusIcon(status: message.status) : null,
          );
          if (isMe) return KeyedSubtree(key: ValueKey(message.messageId), child: bubble);
          return GestureDetector(
            key: ValueKey(message.messageId),
            onLongPress: () => _reportMessage(message.messageId),
            child: bubble,
          );
        },
      );
    }
    if (state is GroupChatErrorState) {
      return ErrorStateView(key: const ValueKey('group-chat-error'), message: state.message);
    }
    return const SizedBox.shrink(key: ValueKey('group-chat-blank'));
  }
}
