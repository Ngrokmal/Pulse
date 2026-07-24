import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../domain/entities/chat_list_item_entity.dart';
import '../../domain/repositories/chat_list_repository.dart';
import '../../domain/usecases/stream_chat_list_usecase.dart';

// Stability + Loading + Error Handling মাইলস্টোন: ChatBloc-এর একই
// load-timeout ধ্রুবক। ChatListRepositoryImpl.streamChatList দুটো Firestore
// query (participantChats + memberGroups) merge করে — দুটোই প্রথম snapshot
// না পাঠানো পর্যন্ত এই স্ট্রিম কোনো ডেটা emit করে না, তাই একটি silently
// hang করলে (permission/index সমস্যা) ChatListLoading চিরকাল আটকে থাকতে
// পারত — এই গার্ড সেটা প্রতিরোধ করে।
const _kLoadTimeout = Duration(seconds: 15);

abstract class ChatListEvent {}

class LoadChatListEvent extends ChatListEvent {
  final String currentUserId;
  LoadChatListEvent(this.currentUserId);
}

/// ইউজার সার্চ বক্সে টাইপ করলে ডিসপ্যাচ হয়। Firestore-এ নতুন query না পাঠিয়ে
/// ইতিমধ্যে স্ট্রিম হওয়া লিস্টের ওপর ক্লায়েন্ট-সাইড ফিল্টার প্রয়োগ করে (রিয়েল-টাইম
/// সাবস্ক্রিপশন অক্ষুণ্ণ থাকে, অতিরিক্ত read cost হয় না)।
class SearchChatListEvent extends ChatListEvent {
  final String query;
  SearchChatListEvent(this.query);
}

abstract class ChatListState {}

class ChatListInitial extends ChatListState {}

class ChatListLoading extends ChatListState {}

class ChatListLoadedState extends ChatListState {
  /// UI-তে দেখানো (ফিল্টার হওয়া) লিস্ট।
  final List<ChatListItemEntity> chats;

  /// বর্তমানে অ্যাক্টিভ সার্চ কোয়েরি — খালি হলে সার্চ বন্ধ, পুরো লিস্ট দেখানো হয়।
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

  // Firestore থেকে সর্বশেষ আসা আনফিল্টার্ড লিস্ট — SearchChatListEvent আসার সময়
  // stream থেকে নতুন ডেটা না এসেও এই ক্যাশের ওপর ফিল্টার প্রয়োগ করা যায়।
  List<ChatListItemEntity> _latestChats = [];
  String _searchQuery = '';
  // Stability fix: ChatBloc._loadTimeoutTimer-এর সমতুল্য।
  Timer? _loadTimeoutTimer;

  ChatListBloc({
    required this.chatListRepository,
    required this.streamChatListUseCase,
  }) : super(ChatListInitial()) {
    on<LoadChatListEvent>((event, emit) async {
      emit(ChatListLoading());

      // Stability fix (Prevent infinite loading): নিচে emit.forEach-এ প্রথম
      // merged snapshot ১৫s-এর মধ্যে না এলে retry-able error emit হয়; স্ট্রিম
      // চালু থাকে, দেরিতে ডেটা এলে self-heal করে (ChatBloc-এর একই প্যাটার্ন)।
      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (!firstSnapshotReceived && !emit.isDone) {
          emit(ChatListErrorState(message: 'লোড হতে সময় বেশি লাগছে। আবার চেষ্টা করুন।'));
        }
      });

      await emit.forEach<List<ChatListItemEntity>>(
        streamChatListUseCase(event.currentUserId),
        onData: (chats) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          _latestChats = chats;
          return ChatListLoadedState(
            chats: _filtered(chats, _searchQuery),
            searchQuery: _searchQuery,
          );
        },
        onError: (error, stackTrace) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          return ChatListErrorState(message: friendlyErrorMessage(error));
        },
      );
      _loadTimeoutTimer?.cancel();
    });

    on<SearchChatListEvent>((event, emit) async {
      _searchQuery = event.query;
      // লোডিং/এরর অবস্থায় সার্চ ইভেন্ট এলে বর্তমান state অপরিবর্তিত রাখা হয়;
      // শুধু ChatListLoadedState-এ থাকা অবস্থায় ফিল্টার প্রযোজ্য।
      if (state is ChatListLoadedState) {
        emit(ChatListLoadedState(
          chats: _filtered(_latestChats, _searchQuery),
          searchQuery: _searchQuery,
        ));
      }
    });
  }

  /// [lastMessage]-এর ওপর কেস-ইনসেনসিটিভ সাবস্ট্রিং ম্যাচ। খালি query হলে
  /// পুরো লিস্ট ফেরত দেয়। (ChatListItemEntity-তে এখনো contact display-name
  /// নেই — সেটা যোগ করতে হলে user-directory join লাগবে, যা আলাদা approval-সাপেক্ষ
  /// আর্কিটেকচার সিদ্ধান্ত — README.md গোল্ডেন রুল #৫।)
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
    // Stability fix (Shared repository lifecycle): ChatBloc/GroupChatBloc-এর
    // একই ক্লাসের bug — ChatListRepository DI-তে lazy singleton, এবং
    // streamChatList-এর instance-level _participantChatsSubscription/
    // _memberGroupsSubscription ফিল্ড সর্বশেষ কলে ওভাররাইট হয়। আগে এখানে
    // `await chatListRepository.close();` কল হতো, যা তাত্ত্বিকভাবে অন্য কোনো
    // সক্রিয় ChatListBloc-এর স্ট্রিম বাতিল করে দিতে পারত। streamChatList-এর
    // নিজস্ব StreamController.onCancel ইতিমধ্যেই bloc বন্ধ হলে (emit.forEach
    // subscription cancel-এর মাধ্যমে) উভয় Firestore সাবস্ক্রিপশন সঠিকভাবে
    // cleanup করে — repository.close() রিডানড্যান্ট ও বিপজ্জনক ছিল।
    return super.close();
  }
}
