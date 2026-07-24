import '../repositories/group_repository.dart';

/// Day 6 Milestone 1 (Typing Indicator): SetTypingStatusUseCase-এর
/// group-সমতুল্য পাতলা wrapper।
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
