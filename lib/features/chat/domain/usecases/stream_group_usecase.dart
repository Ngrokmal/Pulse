import '../entities/group_entity.dart';
import '../repositories/group_repository.dart';

/// StreamGroupMessagesUseCase-এর মতোই পাতলা wrapper, শুধু group metadata স্ট্রিমের জন্য।
class StreamGroupUseCase {
  final GroupRepository repository;
  const StreamGroupUseCase(this.repository);

  Stream<GroupEntity> call(String groupId) {
    return repository.streamGroup(groupId);
  }
}
