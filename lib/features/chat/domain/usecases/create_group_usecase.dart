import '../../../../core/utils/moderation_guard.dart';
import '../repositories/group_repository.dart';

/// GROUP_CHAT_ALGORITHM.md ধারা ১ (Group তৈরি করা) — V1 বেসিক স্কোপ।
/// অন্যান্য UseCase-এর (SendMessageUseCase, StreamMessagesUseCase) মতো এটি
/// GroupRepository-এর একটি পাতলা wrapper, কোনো অতিরিক্ত ব্যবসায়িক লজিক নেই।
class CreateGroupUseCase {
  final GroupRepository repository;
  final ModerationGuard moderationGuard;
  const CreateGroupUseCase(this.repository, this.moderationGuard);

  /// নতুন group তৈরি করে এবং তার [groupId] রিটার্ন করে।
  Future<String> call({
    required String name,
    required String creatorId,
    required List<String> initialMembers,
  }) async {
    await moderationGuard.ensureNotBlocked(creatorId);
    final groupId = repository.generateGroupId();

    await repository.createGroup(
      groupId: groupId,
      name: name,
      creatorId: creatorId,
      initialMembers: initialMembers,
    );

    return groupId;
  }
}
