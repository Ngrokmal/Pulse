import '../repositories/chat_repository.dart';

class StreamTypingStatusUseCase {
  final ChatRepository repository;
  const StreamTypingStatusUseCase(this.repository);

  Stream<List<String>> call(String chatId) {
    return repository.streamTypingUserIds(chatId);
  }
}
