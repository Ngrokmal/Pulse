class ChatListItemEntity {
  final String chatId;
  final List<String> participantIds;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  // Day 5 Milestone 1: group avatar display। nullable/optional — 1:1 chat
  // ডকুমেন্টে এই ফিল্ড থাকে না, তাই null থাকে (UI fallback icon দেখায়)।
  final String? groupPhotoUrl;
  // Day 5 Milestone 2: combined Home list-এ 1:1 বনাম group entry আলাদা করতে।
  // Firestore-এ নতুন ফিল্ড নয় — memberUids doc থেকে এলে true (parsing-time
  // derive করা হয়, ChatListItemModel.fromJson দেখুন)। ডিফল্ট false, তাই
  // বিদ্যমান 1:1 আচরণ অপরিবর্তিত থাকে।
  final bool isGroup;
  // Day 5 Milestone 2: group doc-এর বিদ্যমান 'name' ফিল্ড (createGroup-এ আগে
  // থেকেই লেখা হয়) — এখন Home list-এ group নাম দেখানোর জন্য parse করা হচ্ছে।
  // 1:1 chat doc-এ এই ফিল্ড থাকে না, তাই null থাকে।
  final String? name;

  const ChatListItemEntity({
    required this.chatId,
    required this.participantIds,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    required this.unreadCount,
    this.groupPhotoUrl,
    this.isGroup = false,
    this.name,
  });
}
