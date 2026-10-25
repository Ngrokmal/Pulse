import '../repositories/chat_repository.dart';

class ResetUnreadCountUseCase {
  final ChatRepository repository;
  const ResetUnreadCountUseCase(this.repository);

  Future<void> call({required String chatId, required String uid}) {
    return repository.resetUnreadCount(chatId: chatId, uid: uid);
  }
}
