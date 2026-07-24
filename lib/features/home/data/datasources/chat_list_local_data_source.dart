import '../../domain/entities/chat_list_item_entity.dart';

abstract class ChatListLocalDataSource {
  Future<void> cacheChatList(String uid, List<ChatListItemEntity> chats);
  List<ChatListItemEntity> getCachedChatList(String uid);
}

class ChatListLocalDataSourceImpl implements ChatListLocalDataSource {
  // ইন-মেমোরি সেফ ডাইরেক্ট ক্যাশ (রিয়েল অ্যাপে হাইভ বা সেয়ার্ড প্রিফারেন্স ইনজেক্ট হবে)
  final Map<String, List<ChatListItemEntity>> _localMemoryStorage = {};

  @override
  Future<void> cacheChatList(String uid, List<ChatListItemEntity> chats) async {
    _localMemoryStorage[uid] = List.from(chats);
  }

  @override
  List<ChatListItemEntity> getCachedChatList(String uid) {
    return _localMemoryStorage[uid] ?? [];
  }
}
