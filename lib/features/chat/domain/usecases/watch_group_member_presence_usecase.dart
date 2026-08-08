import '../../../../core/services/shared_presence_manager.dart';

class WatchGroupMemberPresenceUseCase {
  final SharedPresenceManager presenceManager;
  const WatchGroupMemberPresenceUseCase(this.presenceManager);

  Stream<Map<String, dynamic>> call(String memberUid) {
    return presenceManager.watch(memberUid);
  }
}
