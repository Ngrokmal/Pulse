import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// CreateGroupUseCase-এর মতোই পাতলা wrapper — GroupRepository.addMember-এর ওপর
/// কোনো অতিরিক্ত ব্যবসায়িক লজিক নেই। duplicate-membership check GroupInfoBloc-এ হয়
/// (GroupBloc.CreateGroupRequested-এর validation-কে UseCase-এর বাইরে রাখার
/// প্যাটার্ন অনুসরণ করে)।
class AddMemberUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const AddMemberUseCase(this.repository, this.moderationGuard);

  Future<void> call({required String groupId, required String uid, required String actorUid}) async {
    await moderationGuard.ensureNotBlocked(actorUid);
    return repository.addMember(groupId: groupId, uid: uid);
  }
}
