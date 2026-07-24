import '../repositories/chat_repository.dart';

/// ResetGroupUnreadCountUseCase (Day 5 M4)-এর 1:1-সমতুল্য পাতলা wrapper।
/// Day 5 Milestone 6: 1:1 chat screen ওপেন হলে ChatBloc এটি কল করে বর্তমান
/// user-এর unreadCount 0-এ রিসেট করতে।
class ResetUnreadCountUseCase {
  final ChatRepository repository;
  const ResetUnreadCountUseCase(this.repository);

  Future<void> call({required String chatId, required String uid}) {
    return repository.resetUnreadCount(chatId: chatId, uid: uid);
  }
}
