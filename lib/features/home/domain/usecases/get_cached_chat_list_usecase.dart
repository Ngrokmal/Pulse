import '../entities/chat_list_item_entity.dart';
import '../repositories/chat_list_repository.dart';

class GetCachedChatListUseCase {
  final ChatListRepository repository;
  const GetCachedChatListUseCase(this.repository);

  Future<List<ChatListItemEntity>> call(String currentUserId) {
    return repository.getCachedChatList(currentUserId);
  }
}
