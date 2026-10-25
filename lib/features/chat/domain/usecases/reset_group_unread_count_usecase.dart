import '../repositories/group_repository.dart';

class ResetGroupUnreadCountUseCase {
  final GroupRepository repository;
  const ResetGroupUnreadCountUseCase(this.repository);

  Future<void> call({required String groupId, required String uid}) {
    return repository.resetUnreadCount(groupId: groupId, uid: uid);
  }
}
