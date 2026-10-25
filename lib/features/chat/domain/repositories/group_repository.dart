import '../entities/group_entity.dart';
import '../entities/message_entity.dart';

abstract class GroupRepository {
  String generateGroupId();

  Future<void> createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    required List<String> initialMembers,
  });

  Stream<GroupEntity> streamGroup(String groupId);

  Future<void> addMember({required String groupId, required String uid});

  Future<void> removeMember({required String groupId, required String uid});

  Future<void> leaveGroup({required String groupId, required String uid});

  Future<void> promoteToAdmin({required String groupId, required String uid});
  Future<void> demoteAdmin({required String groupId, required String uid});

  Future<void> updateGroupName({required String groupId, required String name});

  Future<void> updateGroupPhoto({required String groupId, required String photoUrl, required String publicId});

  String generateMessageId(String groupId);

  Future<void> sendGroupMessage({
    required String groupId,
    required String messageId,
    required String senderId,
    required String text,
  });

  Future<void> markMessageAsRead({required String groupId, required String messageId, required String uid});

  Future<void> markMessageAsDelivered({
    required String groupId,
    required String messageId,
  });

  Future<void> resetUnreadCount({required String groupId, required String uid});

  Stream<List<MessageEntity>> streamGroupMessages(String groupId);

  Future<void> setTypingStatus({
    required String groupId,
    required String uid,
    required bool isTyping,
  });

  Stream<List<String>> streamTypingUserIds(String groupId);


  Future<void> editGroupMessage({
    required String groupId,
    required String messageId,
    required String text,
  });

  Future<void> deleteGroupMessage({
    required String groupId,
    required String messageId,
  });

  Future<void> updateAttachmentMetadata({
    required String groupId,
    required String messageId,
    required Map<String, dynamic> fields,
  });

  Future<void> addReaction({
    required String groupId,
    required String messageId,
    required String uid,
    required String reaction,
  });

  Future<void> removeReaction({
    required String groupId,
    required String messageId,
    required String uid,
    required String reaction,
  });

  Future<void> close();
}
