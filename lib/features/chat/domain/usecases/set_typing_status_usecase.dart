import '../repositories/chat_repository.dart';

/// Day 6 Milestone 1 (Typing Indicator): ResetUnreadCountUseCase-এর মতোই
/// পাতলা wrapper — SetGroupTypingStatusUseCase-এর 1:1-সমতুল্য।
class SetTypingStatusUseCase {
  final ChatRepository repository;
  const SetTypingStatusUseCase(this.repository);

  Future<void> call({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) {
    return repository.setTypingStatus(chatId: chatId, uid: uid, isTyping: isTyping);
  }
}
