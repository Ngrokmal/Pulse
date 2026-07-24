import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// RemoveMemberUseCase-এর প্রতিসম wrapper — self-removal-এর জন্য। last-member
/// group-delete ও creator-transfer লজিক repository লেয়ারে transaction-এ হ্যান্ডেল হয়,
/// এই UseCase-এ কোনো অতিরিক্ত ব্যবসায়িক লজিক নেই (CreateGroupUseCase/AddMemberUseCase-এর
/// কনভেনশন অনুযায়ী)।
class LeaveGroupUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const LeaveGroupUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid}) async {
    await moderationGuard.ensureNotBlocked(uid);
    return repository.leaveGroup(groupId: groupId, uid: uid);
  }
}
