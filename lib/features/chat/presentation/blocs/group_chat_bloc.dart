import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/usecases/send_group_message_usecase.dart';
import '../../domain/usecases/reset_group_unread_count_usecase.dart';
import '../../domain/usecases/stream_group_messages_usecase.dart';
import '../../domain/usecases/set_group_typing_status_usecase.dart';
import '../../domain/usecases/stream_group_typing_status_usecase.dart';
import '../../domain/usecases/mark_group_message_as_delivered_usecase.dart';
import '../../domain/usecases/mark_group_message_as_read_usecase.dart';

// Stability + Loading + Error Handling মাইলস্টোন: ChatBloc-এর একই
// timeout ধ্রুবকগুলোর group-সমতুল্য (উপরের ChatBloc-এর কমেন্টে ব্যাখ্যা)।
const _kLoadTimeout = Duration(seconds: 15);
const _kActionTimeout = Duration(seconds: 15);

abstract class GroupChatEvent {}

class LoadGroupMessagesEvent extends GroupChatEvent {
  final String groupId;
  // Day 5 Milestone 4: nullable/optional — পুরনো কোনো call-site থাকলে ভাঙবে না।
  // দেওয়া হলে chat open হওয়ার সাথে সাথে current user-এর unreadCount 0-এ রিসেট হয়।
  final String? currentUserId;
  LoadGroupMessagesEvent(this.groupId, {this.currentUserId});
}

class SendGroupMessageEvent extends GroupChatEvent {
  final String groupId;
  final String senderId;
  final String text;
  SendGroupMessageEvent({
    required this.groupId,
    required this.senderId,
    required this.text,
  });
}

// Day 6 Milestone 1 (Typing Indicator): ChatBloc-এর একই-নামের event-গুলোর
// group-সমতুল্য — GroupChatScreen composer keystroke/inactivity-timeout/send-এ
// dispatch করে।
class GroupTypingStartedEvent extends GroupChatEvent {
  final String groupId;
  final String uid;
  GroupTypingStartedEvent({required this.groupId, required this.uid});
}
class GroupTypingStoppedEvent extends GroupChatEvent {
  final String groupId;
  final String uid;
  GroupTypingStoppedEvent({required this.groupId, required this.uid});
}
// Internal — UI dispatch করে না।
class GroupTypingUsersUpdatedEvent extends GroupChatEvent {
  final List<String> typingUserIds;
  GroupTypingUsersUpdatedEvent(this.typingUserIds);
}

abstract class GroupChatState {}

class GroupChatInitial extends GroupChatState {}

class GroupChatLoading extends GroupChatState {}

class GroupChatLoadedState extends GroupChatState {
  final List<MessageEntity> messages;
  // Day 6 Milestone 1: ChatLoadedState.typingUserIds-এর group-সমতুল্য।
  final List<String> typingUserIds;
  GroupChatLoadedState({required this.messages, this.typingUserIds = const []});
}

class GroupChatErrorState extends GroupChatState {
  final String message;
  GroupChatErrorState({required this.message});
}

/// ChatBloc-এর সাথে হুবহু সামঞ্জস্যপূর্ণ প্যাটার্ন (dedupe-by-messageId + sort),
/// শুধু GroupRepository/Group UseCase-এর ওপর নির্ভরশীল। pagination এই মাইলস্টোনের
/// স্কোপে নেই (1:1-এও pagination বেসিক send/stream-এর পরে আলাদা ধাপে এসেছিল — Phase 3.3)।
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final GroupRepository groupRepository;
  final SendGroupMessageUseCase sendGroupMessageUseCase;
  final StreamGroupMessagesUseCase streamGroupMessagesUseCase;
  // Day 5 Milestone 4
  final ResetGroupUnreadCountUseCase resetGroupUnreadCountUseCase;
  // Day 6 Milestone 1 (Typing Indicator)
  final SetGroupTypingStatusUseCase setGroupTypingStatusUseCase;
  final StreamGroupTypingStatusUseCase streamGroupTypingStatusUseCase;
  // Day 6 Milestone 2 (Delivery Status)
  final MarkGroupMessageAsDeliveredUseCase markGroupMessageAsDeliveredUseCase;
  // Day 6 Milestone 3 (Read Receipts)
  final MarkGroupMessageAsReadUseCase markGroupMessageAsReadUseCase;
  final Map<String, MessageEntity> _messagesCache = {};
  // Day 6 Milestone 1: ChatBloc-এর _typingSubscription প্যাটার্নের group-সমতুল্য।
  StreamSubscription<List<String>>? _typingSubscription;
  // Stability fix: ChatBloc._loadTimeoutTimer-এর group-সমতুল্য।
  Timer? _loadTimeoutTimer;
  String? _groupId;
  String? _selfUid;

  GroupChatBloc({
    required this.groupRepository,
    required this.sendGroupMessageUseCase,
    required this.streamGroupMessagesUseCase,
    required this.resetGroupUnreadCountUseCase,
    required this.setGroupTypingStatusUseCase,
    required this.streamGroupTypingStatusUseCase,
    required this.markGroupMessageAsDeliveredUseCase,
    required this.markGroupMessageAsReadUseCase,
  }) : super(GroupChatInitial()) {
    on<LoadGroupMessagesEvent>((event, emit) async {
      emit(GroupChatLoading());
      // Day 5 Milestone 4: chat open হওয়ার সাথে সাথে unreadCount রিসেট —
      // message stream শুরু হওয়ার আগে fire-and-forget (send/promote-এর মতোই
      // OfflineQueueManager idempotent write, তাই await করে stream block করার
      // দরকার নেই)।
      if (event.currentUserId != null) {
        // Stability fix: OfflineQueueManager এখন real Future রিটার্ন করে —
        // best-effort/self-correcting মার্ক (handoff.md ধারা ৪), তাই
        // .catchError দিয়ে log করা হয়, silently drop নয় (ChatBloc-এর একই fix)।
        resetGroupUnreadCountUseCase(
          groupId: event.groupId,
          uid: event.currentUserId!,
        ).catchError((Object e) {
          debugPrint('GroupChatBloc: resetUnreadCount failed — ${friendlyErrorMessage(e)}');
        });
      }
      _groupId = event.groupId;
      _selfUid = event.currentUserId;

      // Day 6 Milestone 1: ChatBloc.LoadMessagesEvent-এর typing-স্ট্রিম
      // সাবস্ক্রিপশন প্যাটার্নের হুবহু সমতুল্য।
      // TYPING INDICATOR DISABLED (matches ChatBloc): subscription
      // intentionally not started.
      // await _typingSubscription?.cancel();
      // _typingSubscription = streamGroupTypingStatusUseCase(event.groupId).listen(
      //   (typingUserIds) {
      //     final filtered = event.currentUserId == null
      //         ? typingUserIds
      //         : typingUserIds.where((uid) => uid != event.currentUserId).toList();
      //     add(GroupTypingUsersUpdatedEvent(filtered));
      //   },
      //   onError: (Object e) {
      //     debugPrint('GroupChatBloc: typing stream error — ${friendlyErrorMessage(e)}');
      //   },
      // );

      // Stability fix (Prevent infinite loading): ChatBloc.LoadMessagesEvent-এর
      // একই timeout-guard প্যাটার্ন — প্রথম snapshot ১৫s-এর মধ্যে না এলে
      // retry-able error, তারপরও stream চালু থাকে (দেরিতে ডেটা এলে self-heal)।
      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (!firstSnapshotReceived && !emit.isDone) {
          emit(GroupChatErrorState(message: 'লোড হতে সময় বেশি লাগছে। আবার চেষ্টা করুন।'));
        }
      });

      await emit.forEach<List<MessageEntity>>(
        streamGroupMessagesUseCase(event.groupId),
        onData: (messages) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          for (final message in messages) {
            _messagesCache[message.messageId] = message;
            // Day 6 Milestone 2 (Delivery Status): ChatBloc-এর একই লজিকের
            // group-সমতুল্য।
            if (event.currentUserId != null &&
                message.senderId != event.currentUserId &&
                message.status == 'sent') {
              markGroupMessageAsDeliveredUseCase(
                groupId: event.groupId,
                messageId: message.messageId,
                uid: event.currentUserId!,
              ).catchError((Object e) {
                debugPrint('GroupChatBloc: markMessageAsDelivered failed — ${friendlyErrorMessage(e)}');
              });
            }
            // Day 6 Milestone 3 (Read Receipts): ChatBloc-এর একই লজিকের
            // group-সমতুল্য — group screen খোলা অবস্থায় নিজের নয় এমন
            // মেসেজ receive হওয়া মানেই read। uid প্যারামিটার (receipts
            // sub-collection-এর জন্য) currentUserId থেকে আসে।
            if (event.currentUserId != null &&
                message.senderId != event.currentUserId &&
                message.status != 'read') {
              markGroupMessageAsReadUseCase(
                groupId: event.groupId,
                messageId: message.messageId,
                uid: event.currentUserId!,
              ).catchError((Object e) {
                debugPrint('GroupChatBloc: markMessageAsRead failed — ${friendlyErrorMessage(e)}');
              });
            }
          }
          return GroupChatLoadedState(messages: _sortedMessages(), typingUserIds: _currentTypingUserIds);
        },
        onError: (error, stackTrace) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          return GroupChatErrorState(message: friendlyErrorMessage(error));
        },
      );
      _loadTimeoutTimer?.cancel();
    });

    on<SendGroupMessageEvent>((event, emit) async {
      try {
        // Stability fix (Add timeout + Prevent infinite loading): ChatBloc-এর
        // SendMessageEvent-এর একই fix — OfflineQueueManager এখন real Future
        // propagate করে, timeout স্থায়ী নেটওয়ার্ক-ডাউন অবস্থায় হ্যাং এড়ায়।
        await sendGroupMessageUseCase(
          groupId: event.groupId,
          senderId: event.senderId,
          text: event.text,
        ).timeout(_kActionTimeout);
        // Day 6 Milestone 1: send-এর পর অবিলম্বে typing বন্ধ — ChatBloc-এর
        // SendMessageEvent handler-এর হুবহু সমতুল্য।
        // TYPING INDICATOR DISABLED: write removed.
        // setGroupTypingStatusUseCase(groupId: event.groupId, uid: event.senderId, isTyping: false).catchError((Object e) {
        //   debugPrint('GroupChatBloc: setTypingStatus failed — ${friendlyErrorMessage(e)}');
        // });
      } catch (e) {
        emit(GroupChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    // TYPING INDICATOR DISABLED: handlers left registered, bodies no-op.
    on<GroupTypingStartedEvent>((event, emit) {
      // setGroupTypingStatusUseCase(groupId: event.groupId, uid: event.uid, isTyping: true).catchError((Object e) {
      //   debugPrint('GroupChatBloc: setTypingStatus(true) failed — ${friendlyErrorMessage(e)}');
      // });
    });
    on<GroupTypingStoppedEvent>((event, emit) {
      // setGroupTypingStatusUseCase(groupId: event.groupId, uid: event.uid, isTyping: false).catchError((Object e) {
      //   debugPrint('GroupChatBloc: setTypingStatus(false) failed — ${friendlyErrorMessage(e)}');
      // });
    });

    on<GroupTypingUsersUpdatedEvent>((event, emit) {
      _currentTypingUserIds = event.typingUserIds;
      if (state is GroupChatLoadedState) {
        emit(GroupChatLoadedState(
          messages: (state as GroupChatLoadedState).messages,
          typingUserIds: _currentTypingUserIds,
        ));
      }
    });
  }

  List<String> _currentTypingUserIds = [];

  List<MessageEntity> _sortedMessages() {
    return _messagesCache.values.toList()
      ..sort((a, b) {
        final int cmp = a.createdAt.compareTo(b.createdAt);
        if (cmp != 0) return cmp;
        return a.messageId.compareTo(b.messageId);
      });
  }

  @override
  Future<void> close() async {
    // Day 6 Milestone 1: ChatBloc.close()-এর হুবহু সমতুল্য cleanup।
    // TYPING INDICATOR DISABLED: cleanup ping removed.
    // if (_groupId != null && _selfUid != null) {
    //   // ignore: unawaited_futures
    //   setGroupTypingStatusUseCase(groupId: _groupId!, uid: _selfUid!, isTyping: false).catchError((Object e) {
    //     debugPrint('GroupChatBloc: cleanup setTypingStatus failed — ${friendlyErrorMessage(e)}');
    //   });
    // }
    _loadTimeoutTimer?.cancel();
    await _typingSubscription?.cancel();
    // Stability fix (Shared GroupRepository lifecycle — এই মাইলস্টোনের
    // task-এ স্পষ্টভাবে উল্লেখিত bug): handoff.md ধারা ৪-এ documented
    // invariant ছিল "GroupInfoBloc/GroupChatBloc shared repository ব্যবহার
    // করে, কেউ close() override করে shared resource বন্ধ করে না" — কিন্তু
    // এই মেথড আগে ঠিক সেটাই করত (`await groupRepository.close();`)।
    // GroupRepository DI-তে lazy singleton — streamGroupMessages/
    // streamTypingUserIds প্রতিটি কলে instance-level
    // `_groupMessagesSubscription`/`_typingSubscription` ফিল্ড সর্বশেষ
    // subscription-এ ওভাররাইট হয়। দুটো GroupChatScreen একই সাথে (বা দ্রুত
    // পরপর) খোলা থাকলে একটি bloc.close() অন্য group-এর সক্রিয় স্ট্রিম বাতিল
    // করে দিতে পারত (cross-talk)। প্রতিটি stream নিজের
    // StreamController.onCancel দিয়ে ইতিমধ্যেই নিজের Firestore subscription
    // সঠিকভাবে cleanup করে (emit.forEach/এই bloc-এর নিজস্ব _typingSubscription
    // cancel-এর মাধ্যমে) — repository.close() রিডানড্যান্ট ও বিপজ্জনক ছিল,
    // তাই সরানো হয়েছে (GroupInfoBloc-এর ইতিমধ্যে-সঠিক প্যাটার্নের সাথে
    // এখন সামঞ্জস্যপূর্ণ)।
    return super.close();
  }
}
