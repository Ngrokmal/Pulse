import '../repositories/chat_repository.dart';

/// Resolves the 1:1 chatId for two users, creating the underlying
/// `chats/{chatId}` document on first contact (idempotent — the same pair
/// of users always resolves to the same conversation). Thin repository
/// wrapper, same shape as CreateGroupUseCase/SendMessageUseCase — no
/// additional business logic.
class GetOrCreateDirectChatUseCase {
  final ChatRepository repository;
  const GetOrCreateDirectChatUseCase(this.repository);

  Future<String> call({required String uidA, required String uidB}) async {
    final chatId = repository.generateDirectChatId(uidA: uidA, uidB: uidB);
    await repository.ensureDirectChatExists(chatId: chatId, uidA: uidA, uidB: uidB);
    return chatId;
  }
}
