import '../repositories/chat_repository.dart';

class GetOrCreateDirectChatUseCase {
  final ChatRepository repository;
  const GetOrCreateDirectChatUseCase(this.repository);

  Future<String> call({required String uidA, required String uidB}) async {
    final chatId = repository.generateDirectChatId(uidA: uidA, uidB: uidB);
    await repository.ensureDirectChatExists(chatId: chatId, uidA: uidA, uidB: uidB);
    return chatId;
  }
}
