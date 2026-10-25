import '../entities/chat_list_item_entity.dart';
import '../repositories/chat_list_repository.dart';

class StreamChatListUseCase {
  final ChatListRepository repository;
  const StreamChatListUseCase(this.repository);

  Stream<List<ChatListItemEntity>> call(String currentUserId) {
    return repository.streamChatList(currentUserId);
  }
}
