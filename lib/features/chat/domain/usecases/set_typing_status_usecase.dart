import '../repositories/chat_repository.dart';

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
