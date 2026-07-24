import '../repositories/group_repository.dart';

/// PromoteAdminUseCase-এর মতোই পাতলা wrapper। Day 5 Milestone 4: group chat
/// screen ওপেন হলে GroupChatBloc এটি কল করে বর্তমান user-এর unreadCount 0-এ
/// রিসেট করতে।
class ResetGroupUnreadCountUseCase {
  final GroupRepository repository;
  const ResetGroupUnreadCountUseCase(this.repository);

  Future<void> call({required String groupId, required String uid}) {
    return repository.resetUnreadCount(groupId: groupId, uid: uid);
  }
}
