import '../entities/message_entity.dart';
import '../repositories/group_repository.dart';

class StreamGroupMessagesUseCase {
  final GroupRepository repository;
  const StreamGroupMessagesUseCase(this.repository);

  Stream<List<MessageEntity>> call(String groupId) {
    return repository.streamGroupMessages(groupId);
  }
}
