import '../repositories/group_repository.dart';

class StreamGroupTypingStatusUseCase {
  final GroupRepository repository;
  const StreamGroupTypingStatusUseCase(this.repository);

  Stream<List<String>> call(String groupId) {
    return repository.streamTypingUserIds(groupId);
  }
}
