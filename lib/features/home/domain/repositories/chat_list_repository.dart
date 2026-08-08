import '../entities/chat_list_item_entity.dart';

abstract class ChatListRepository {
  Stream<List<ChatListItemEntity>> streamChatList(String currentUserId);

  Future<List<ChatListItemEntity>> getCachedChatList(String currentUserId);

  void invalidateFriendIdsCache([String? myUuid]);

  Future<void> close();
}
