import '../entities/message_entity.dart';

abstract class ChatRepository {
  /// একটি নতুন Firestore auto-generated message ID reserve করে
  /// (`chats/{chatId}/messages` কালেকশনের আন্ডারে) — কোনো write হয় না।
  /// GroupRepository.generateMessageId-এর 1:1-সমতুল্য। Day 6 M1 composer-fix:
  /// আগে এই মেথড ছিল না বলে 1:1 পাশে কোনো messageId generation-পথ ছিল না
  /// (handoff.md ধারা ৬-এ চিহ্নিত gap) — SendMessageUseCase-এ ব্যবহৃত হয়,
  /// SendGroupMessageUseCase-এর প্যাটার্নের সাথে সামঞ্জস্যপূর্ণ।
  String generateMessageId(String chatId);

  Future<void> sendMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
  });

  Future<void> sendMediaMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String type,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
    String? fileName,
    int? fileSizeBytes,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    List<double>? waveform,
  });

  /// Friend Alert Sounds (Premium Social Feature) — additive sibling of
  /// [sendMessage]/[sendMediaMessage], same generateMessageId()+_persistMessage
  /// pattern under the hood. Supports all three send modes from a single
  /// entry point: message-only (alert params omitted — callers should use
  /// [sendMessage] instead), alert-only ([text] empty), and message+alert
  /// ([text] non-empty). [alertAudioUrl]/[alertAudioChecksum] etc. mirror
  /// AlertAudioMetadata 1:1 (custom_alert/domain/entities/
  /// alert_audio_metadata_entity.dart) — reused, not redefined.
  Future<void> sendMessageWithAlert({
    required String chatId,
    required String messageId,
    required String senderId,
    String text = '',
    required String alertId,
    required String alertDisplayName,
    required String alertAudioUrl,
    required String alertAudioChecksum,
    required String alertAudioFormat,
    required int alertAudioSizeBytes,
    int? alertAudioDurationMs,
  });

  /// Day 5 Milestone 6: 1:1 chat screen ওপেন হলে কল হয় — বর্তমান user-এর
  /// `unreadCount.{uid}` 0-এ রিসেট করে। `sendMessage` বাকি participant(দের)
  /// unreadCount বাড়ায় (sender বাদে); এই মেথড শুধু reset করে। GroupRepository-এর
  /// একই নামের/সিগনেচারের মেথডের 1:1-সমতুল্য (Day 5 M4)।
  Future<void> resetUnreadCount({required String chatId, required String uid});

  /// Day 6 Milestone 1 (Typing Indicator): `chats/{chatId}` ডকুমেন্টের
  /// `typingUserIds` array-এ uid যোগ/বাদ দেয় (isTyping true হলে arrayUnion,
  /// false হলে arrayRemove) — GroupRepository-এর একই-নামের মেথডের 1:1-সমতুল্য,
  /// এবং addMember/removeMember-এর arrayUnion/arrayRemove প্যাটার্নের পুনঃব্যবহার।
  /// ইচ্ছাকৃতভাবে `OfflineQueueManager` ব্যবহার করা হয়নি — typing status
  /// ephemeral/real-time; queue করলে অফলাইন থেকে reconnect হওয়ার পর পুরনো/stale
  /// typing:true ping দেরিতে ডেলিভার হতে পারত, যা unreadCount-এর মতো
  /// eventual-consistency-সহনশীল ডেটার জন্য ঠিক থাকলেও typing indicator-এর
  /// জন্য UX-এ ভুল সিগন্যাল দিত।
  Future<void> setTypingStatus({
    required String chatId,
    required String uid,
    required bool isTyping,
  });

  /// Day 6 Milestone 1: `chats/{chatId}` ডকুমেন্টের `typingUserIds` array-এর
  /// রিয়েলটাইম স্ট্রিম (raw uid list, self-uid ফিল্টারিং কলার/Bloc-এর দায়িত্ব)।
  Stream<List<String>> streamTypingUserIds(String chatId);

  /// Day 6 Milestone 2 (Delivery Status): recipient client message receive
  /// করলে কল হয় — নির্দিষ্ট মেসেজের `status` ফিল্ড 'delivered'-এ সেট করে।
  /// GroupRepository-এর একই-নামের মেথডের 1:1-সমতুল্য। resetUnreadCount/
  /// setTypingStatus-এর মতোই সরল single-field `.update()` প্যাটার্ন।
  Future<void> markMessageAsDelivered({
    required String chatId,
    required String messageId,
  });

  /// Day 6 Milestone 3 (Read Receipts): recipient client message দেখলে
  /// (chat screen খোলা অবস্থায় stream-এ receive হলে) কল হয় — নির্দিষ্ট
  /// মেসেজের `status` ফিল্ড 'read'-এ সেট করে। markMessageAsDelivered-এর
  /// হুবহু সমতুল্য single-field `.update()` প্যাটার্ন — GroupRepository-এর
  /// একই-নামের মেথডের 1:1-সমতুল্য।
  Future<void> markMessageAsRead({
    required String chatId,
    required String messageId,
  });

  Stream<List<MessageEntity>> streamMessages(String chatId);

  /// Loads a page of messages older than [beforeCreatedAt], for
  /// FIRESTORE_SCHEMA.md-style pagination (newest-first page, limited size).
  Future<List<MessageEntity>> loadOlderMessages({
    required String chatId,
    required DateTime beforeCreatedAt,
    int limit = 30,
  });

  /// Deterministic 1:1 chatId derived from both participant uids (sorted so
  /// order doesn't matter) — GroupRepository.generateGroupId's 1:1-equivalent,
  /// except deterministic instead of random-auto-id, since two given users
  /// must always resolve to the *same* conversation document.
  String generateDirectChatId({required String uidA, required String uidB});

  /// Creates the `chats/{chatId}` document for a 1:1 conversation if it
  /// doesn't already exist (idempotent no-op otherwise). Before this, no
  /// code path ever wrote `participantIds` for a 1:1 chat doc — sendMessage's
  /// `_persistMessage` only `.set(merge:true)`s lastMessage/lastMessageAt/
  /// unreadCount fields, so a 1:1 chat could never appear in
  /// ChatListRepositoryImpl's `participantIds arrayContains` query, and the
  /// Message button had nothing to navigate to.
  Future<void> ensureDirectChatExists({
    required String chatId,
    required String uidA,
    required String uidB,
  });

  Future<void> close();
}
