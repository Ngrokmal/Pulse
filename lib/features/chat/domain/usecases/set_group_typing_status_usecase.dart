import '../repositories/group_repository.dart';

class SetGroupTypingStatusUseCase {
  final GroupRepository repository;
  const SetGroupTypingStatusUseCase(this.repository);

  Future<void> call({
    required String groupId,
    required String uid,
    required bool isTyping,
  }) {
    return repository.setTypingStatus(groupId: groupId, uid: uid, isTyping: isTyping);
  }
}
