import '../entities/message_entity.dart';
import '../repositories/chat_repository.dart';

class StreamMessagesUseCase {
  final ChatRepository repository;
  const StreamMessagesUseCase(this.repository);

  Stream<List<MessageEntity>> call(String chatId) {
    return repository.streamMessages(chatId);
  }
}
