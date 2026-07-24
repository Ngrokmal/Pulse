import '../entities/chat_list_item_entity.dart';

abstract class ChatListRepository {
  Stream<List<ChatListItemEntity>> streamChatList(String currentUserId);
  Future<void> close();
}
