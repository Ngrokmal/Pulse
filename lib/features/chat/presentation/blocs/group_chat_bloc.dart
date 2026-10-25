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

const _kLoadTimeout = Duration(seconds: 15);
const _kActionTimeout = Duration(seconds: 15);

abstract class GroupChatEvent {}

class LoadGroupMessagesEvent extends GroupChatEvent {
  final String groupId;
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
class GroupTypingUsersUpdatedEvent extends GroupChatEvent {
  final List<String> typingUserIds;
  GroupTypingUsersUpdatedEvent(this.typingUserIds);
}

abstract class GroupChatState {}

class GroupChatInitial extends GroupChatState {}

class GroupChatLoading extends GroupChatState {}

class GroupChatLoadedState extends GroupChatState {
  final List<MessageEntity> messages;
  final List<String> typingUserIds;
  GroupChatLoadedState({required this.messages, this.typingUserIds = const []});
}

class GroupChatErrorState extends GroupChatState {
  final String message;
  GroupChatErrorState({required this.message});
}

class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final GroupRepository groupRepository;
  final SendGroupMessageUseCase sendGroupMessageUseCase;
  final StreamGroupMessagesUseCase streamGroupMessagesUseCase;
  final ResetGroupUnreadCountUseCase resetGroupUnreadCountUseCase;
  final SetGroupTypingStatusUseCase setGroupTypingStatusUseCase;
  final StreamGroupTypingStatusUseCase streamGroupTypingStatusUseCase;
  final MarkGroupMessageAsDeliveredUseCase markGroupMessageAsDeliveredUseCase;
  final MarkGroupMessageAsReadUseCase markGroupMessageAsReadUseCase;
  final Map<String, MessageEntity> _messagesCache = {};
  StreamSubscription<List<String>>? _typingSubscription;
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
      if (event.currentUserId != null) {
        resetGroupUnreadCountUseCase(
          groupId: event.groupId,
          uid: event.currentUserId!,
        ).catchError((Object e) {
          debugPrint('GroupChatBloc: resetUnreadCount failed — ${friendlyErrorMessage(e)}');
        });
      }
      _groupId = event.groupId;
      _selfUid = event.currentUserId;


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
        await sendGroupMessageUseCase(
          groupId: event.groupId,
          senderId: event.senderId,
          text: event.text,
        ).timeout(_kActionTimeout);
      } catch (e) {
        emit(GroupChatErrorState(message: friendlyErrorMessage(e)));
      }
    });

    on<GroupTypingStartedEvent>((event, emit) {
    });
    on<GroupTypingStoppedEvent>((event, emit) {
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
    _loadTimeoutTimer?.cancel();
    await _typingSubscription?.cancel();
    return super.close();
  }
}
