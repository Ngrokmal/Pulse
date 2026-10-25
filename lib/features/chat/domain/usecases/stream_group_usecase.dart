import '../entities/group_entity.dart';
import '../repositories/group_repository.dart';

class StreamGroupUseCase {
  final GroupRepository repository;
  const StreamGroupUseCase(this.repository);

  Stream<GroupEntity> call(String groupId) {
    return repository.streamGroup(groupId);
  }
}
