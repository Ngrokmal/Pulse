import '../repositories/chat_repository.dart';

/// Day 6 Milestone 1 (Typing Indicator): StreamMessagesUseCase-এর মতোই
/// পাতলা wrapper — StreamGroupTypingStatusUseCase-এর 1:1-সমতুল্য।
class StreamTypingStatusUseCase {
  final ChatRepository repository;
  const StreamTypingStatusUseCase(this.repository);

  Stream<List<String>> call(String chatId) {
    return repository.streamTypingUserIds(chatId);
  }
}
