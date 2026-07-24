import '../entities/group_entity.dart';
import '../entities/message_entity.dart';

abstract class GroupRepository {
  /// একটি নতুন Firestore auto-generated document ID তৈরি করে (`chats` কালেকশনের
  /// আন্ডারে), যা `createGroup`-এ `groupId` হিসেবে ব্যবহার করা হয়। এটি শুধুমাত্র
  /// একটি ID reserve করে — কোনো ডকুমেন্ট write করে না।
  String generateGroupId();

  Future<void> createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    required List<String> initialMembers,
  });

  /// Milestone 3 (Group Info): `chats/{groupId}` ডকুমেন্টের রিয়েলটাইম স্ট্রিম।
  /// Group Info স্ক্রিন ও Member List উভয়ই এই একই স্ট্রিম ব্যবহার করে, কারণ
  /// `memberUids` cached array (createGroup/addMember/removeMember সবকটিই এটিকে
  /// transaction/batch-এ members sub-collection-এর সাথে sync রাখে) V1 স্কোপের
  /// জন্য যথেষ্ট authoritative — আলাদা sub-collection স্ট্রিমের প্রয়োজন নেই।
  Stream<GroupEntity> streamGroup(String groupId);

  Future<void> addMember({required String groupId, required String uid});

  /// GROUP_CHAT_ALGORITHM.md ধারা ৫ (Remove) — V1 বেসিক স্কোপ: শুধু storage-লেয়ার
  /// mutation (members sub-collection ডকুমেন্ট ডিলিট + cached array remove,
  /// addMember-এর মতোই transaction-এ)। admin-permission gating, system message,
  /// এবং removed-user local cache eviction (Cloud Function trigger) এখনো
  /// পরিকল্পিত — GROUP_CHAT_ALGORITHM.md ধারা ৫-এ স্পষ্টভাবে "পরিকল্পিত" হিসেবে চিহ্নিত।
  Future<void> removeMember({required String groupId, required String uid});

  /// Milestone 4 (Leave Group): removeMember-এর মতোই member-removal, কিন্তু
  /// self-removal-এর জন্য — এবং দুটো অতিরিক্ত রুল transaction-এ হ্যান্ডেল করে:
  /// (১) leaving user শেষ member হলে পুরো group document ডিলিট হয়ে যায়
  /// (২) leaving user creator হলে ও group survive করলে পরবর্তী remaining
  /// member (memberUids array-এর পরবর্তী uid) নতুন creator হিসেবে promote হয়।
  /// কোনো admin/role সিস্টেম না থাকায় (Milestone 5-এ পরিকল্পিত) এটিই একমাত্র
  /// ownership-transfer রুল। messages sub-collection cleanup হয় না — জানা সীমাবদ্ধতা।
  Future<void> leaveGroup({required String groupId, required String uid});

  /// Milestone 5 (Admin roles): `adminIds` array-এ uid যোগ/বাদ দেয়। permission
  /// check (কে promote/demote করতে পারবে) ও creator/last-admin গার্ড
  /// GroupInfoBloc-এ হয় (removeMember-এর creator-guard-এর মতোই প্যাটার্ন) —
  /// এই মেথড দুটো নিজে কোনো গার্ড রাখে না, শুধু raw array mutation।
  Future<void> promoteToAdmin({required String groupId, required String uid});
  Future<void> demoteAdmin({required String groupId, required String uid});

  /// Milestone 6 (Edit group name/photo): raw Firestore mutation only — কোনো
  /// permission গার্ড এখানে নেই (promoteToAdmin/demoteAdmin-এর মতোই প্যাটার্ন,
  /// admin-only check GroupInfoBloc-এ হয়)।
  Future<void> updateGroupName({required String groupId, required String name});

  /// `photoUrl` = Cloudinary `secure_url`, `publicId` = Cloudinary `public_id`।
  /// পুরনো asset ডিলিট করার সিদ্ধান্ত এখানে হয় না — GroupInfoBloc আগের
  /// `groupPhotoPublicId` cache থেকে পড়ে, এই মেথড কল করে নতুনটা persist করার
  /// পর, MediaRepository দিয়ে আলাদাভাবে পুরনোটা ডিলিট করে (best-effort)।
  Future<void> updateGroupPhoto({required String groupId, required String photoUrl, required String publicId});

  /// একটি নতুন Firestore auto-generated message ID reserve করে
  /// (`chats/{groupId}/messages` কালেকশনের আন্ডারে) — কোনো write হয় না।
  String generateMessageId(String groupId);

  /// CHAT_ALGORITHM.md-এর মূল send pipeline-এর সাথে সামঞ্জস্যপূর্ণ (GROUP_CHAT_ALGORITHM.md
  /// ধারা ২: pipeline একই, শুধু receipt/permission অংশে পার্থক্য — V1-এ receipt/permission
  /// এখনো implement হয়নি, শুধু plain send)।
  Future<void> sendGroupMessage({
    required String groupId,
    required String messageId,
    required String senderId,
    required String text,
  });

  /// Day 6 Milestone 3 (Read Receipts): per-uid `receipts` sub-collection-এ
  /// readAt লেখে (পূর্ব-বিদ্যমান স্বাক্ষর/আচরণ অপরিবর্তিত) এবং একই সাথে
  /// message doc-এর shared `status` ফিল্ড 'read'-এ সেট করে (UI-এর জন্য,
  /// markMessageAsDelivered-এর per-member-granular-নয় সিদ্ধান্তের সাথে
  /// সামঞ্জস্যপূর্ণ — প্রথম non-sender read-ই যথেষ্ট)।
  Future<void> markMessageAsRead({required String groupId, required String messageId, required String uid});

  /// Day 6 Milestone 2 (Delivery Status): ChatRepository.markMessageAsDelivered-এর
  /// group-সমতুল্য — কোনো per-uid granularity নেই (markMessageAsRead-এর
  /// receipts sub-collection প্যাটার্নের বিপরীতে), শুধু single `status`
  /// ফিল্ড 'delivered'-এ সেট হয় প্রথম non-sender member receive করার সাথে সাথে
  /// (WhatsApp-এর single-tick→double-tick মডেল, per-member read-receipt নয়)।
  Future<void> markMessageAsDelivered({
    required String groupId,
    required String messageId,
  });

  /// Day 5 Milestone 4: group chat screen ওপেন হলে (LoadGroupMessagesEvent-এর
  /// সাথে) কল হয় — বর্তমান user-এর `unreadCount.{uid}` 0-এ রিসেট করে। sendGroupMessage
  /// বাকি member-দের unreadCount বাড়ায় (sender বাদে); এই মেথড শুধু reset করে।
  Future<void> resetUnreadCount({required String groupId, required String uid});

  Stream<List<MessageEntity>> streamGroupMessages(String groupId);

  /// Day 6 Milestone 1 (Typing Indicator): ChatRepository.setTypingStatus-এর
  /// group-সমতুল্য — `chats/{groupId}` ডকুমেন্টের `typingUserIds` array-এ
  /// promoteToAdmin/demoteAdmin-এর arrayUnion/arrayRemove প্যাটার্ন পুনঃব্যবহার
  /// করা হয়েছে। OfflineQueueManager ইচ্ছাকৃতভাবে ব্যবহৃত হয়নি (কারণ
  /// ChatRepository.setTypingStatus-এর doc-এ ব্যাখ্যা করা হয়েছে)।
  Future<void> setTypingStatus({
    required String groupId,
    required String uid,
    required bool isTyping,
  });

  /// ChatRepository.streamTypingUserIds-এর group-সমতুল্য।
  Stream<List<String>> streamTypingUserIds(String groupId);

  Future<void> close();
}
