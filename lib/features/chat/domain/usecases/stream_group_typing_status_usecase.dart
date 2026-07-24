import '../repositories/group_repository.dart';

/// Day 6 Milestone 1 (Typing Indicator): StreamTypingStatusUseCase-এর
/// group-সমতুল্য পাতলা wrapper।
class StreamGroupTypingStatusUseCase {
  final GroupRepository repository;
  const StreamGroupTypingStatusUseCase(this.repository);

  Stream<List<String>> call(String groupId) {
    return repository.streamTypingUserIds(groupId);
  }
}
