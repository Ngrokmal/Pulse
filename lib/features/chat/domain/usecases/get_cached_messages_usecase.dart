import '../entities/message_entity.dart';
import '../repositories/chat_repository.dart';

class GetCachedMessagesUseCase {
  final ChatRepository repository;
  const GetCachedMessagesUseCase(this.repository);

  Future<List<MessageEntity>> call(String chatId) {
    return repository.getCachedMessages(chatId);
  }
}
