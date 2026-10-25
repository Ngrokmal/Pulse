import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/profile_bulk_warmup_service.dart';
import '../../domain/entities/chat_list_item_entity.dart';
import '../../domain/repositories/chat_list_repository.dart';
import '../../domain/usecases/stream_chat_list_usecase.dart';
import '../../domain/usecases/get_cached_chat_list_usecase.dart';

const _kLoadTimeout = Duration(seconds: 15);

const _kWarmupThrottle = Duration(minutes: 15);

abstract class ChatListEvent {}

class LoadChatListEvent extends ChatListEvent {
  final String currentUserId;
  LoadChatListEvent(this.currentUserId);
}

class SearchChatListEvent extends ChatListEvent {
  final String query;
  SearchChatListEvent(this.query);
}

abstract class ChatListState {}

class ChatListInitial extends ChatListState {}

class ChatListLoading extends ChatListState {}

class ChatListLoadedState extends ChatListState {
  final List<ChatListItemEntity> chats;
  final String searchQuery;

  ChatListLoadedState({required this.chats, this.searchQuery = ''});
}

class ChatListErrorState extends ChatListState {
  final String message;
  ChatListErrorState({required this.message});
}

class ChatListBloc extends Bloc<ChatListEvent, ChatListState> {
  final ChatListRepository chatListRepository;
  final StreamChatListUseCase streamChatListUseCase;
  final GetCachedChatListUseCase getCachedChatListUseCase;
  final ProfileBulkWarmupService profileBulkWarmupService;

  List<ChatListItemEntity> _latestChats = [];
  String _searchQuery = '';
  Timer? _loadTimeoutTimer;
  DateTime? _lastWarmupAt;

  ChatListBloc({
    required this.chatListRepository,
    required this.streamChatListUseCase,
    required this.getCachedChatListUseCase,
    required this.profileBulkWarmupService,
  }) : super(ChatListInitial()) {
    on<LoadChatListEvent>((event, emit) async {
      final cached = await getCachedChatListUseCase(event.currentUserId);
      if (cached.isNotEmpty) {
        _latestChats = cached;
        emit(ChatListLoadedState(
          chats: _filtered(cached, _searchQuery),
          searchQuery: _searchQuery,
        ));
        _maybeWarmUp(cached, event.currentUserId);
      } else {
        emit(ChatListLoading());
      }

      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (firstSnapshotReceived || emit.isDone) return;
        if (state is ChatListLoadedState) return;
        emit(ChatListLoadedState(
          chats: _filtered(_latestChats, _searchQuery),
          searchQuery: _searchQuery,
        ));
      });

      await emit.forEach<List<ChatListItemEntity>>(
        streamChatListUseCase(event.currentUserId),
        onData: (chats) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          _latestChats = chats;
          _maybeWarmUp(chats, event.currentUserId);
          return ChatListLoadedState(
            chats: _filtered(chats, _searchQuery),
            searchQuery: _searchQuery,
          );
        },
        onError: (error, stackTrace) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          return ChatListLoadedState(
            chats: _filtered(_latestChats, _searchQuery),
            searchQuery: _searchQuery,
          );
        },
      );
      _loadTimeoutTimer?.cancel();
    });

    on<SearchChatListEvent>((event, emit) async {
      _searchQuery = event.query;
      if (state is ChatListLoadedState) {
        emit(ChatListLoadedState(
          chats: _filtered(_latestChats, _searchQuery),
          searchQuery: _searchQuery,
        ));
      }
    });
  }

  void _maybeWarmUp(List<ChatListItemEntity> chats, String currentUserId) {
    final now = DateTime.now();
    if (_lastWarmupAt != null && now.difference(_lastWarmupAt!) < _kWarmupThrottle) {
      return;
    }
    _lastWarmupAt = now;
    unawaited(profileBulkWarmupService.warmUpProfiles(_collectFriendUids(chats, currentUserId)));
  }

  Set<String> _collectFriendUids(List<ChatListItemEntity> chats, String currentUserId) {
    final uids = <String>{};
    for (final chat in chats) {
      if (chat.isGroup) continue;
      final other = chat.participantIds.firstWhere((id) => id != currentUserId, orElse: () => '');
      if (other.isNotEmpty) uids.add(other);
    }
    return uids;
  }

  List<ChatListItemEntity> _filtered(List<ChatListItemEntity> source, String query) {
    if (query.trim().isEmpty) return source;
    final normalized = query.trim().toLowerCase();
    return source
        .where((chat) => chat.lastMessage.toLowerCase().contains(normalized))
        .toList();
  }

  @override
  Future<void> close() async {
    _loadTimeoutTimer?.cancel();
    return super.close();
  }
}