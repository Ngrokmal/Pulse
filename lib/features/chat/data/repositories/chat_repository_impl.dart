import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/network/offline_queue.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../datasources/chat_local_data_source.dart';
import '../models/message_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource remoteDataSource;
  final ChatLocalDataSource localDataSource;
  final FirebaseFirestore firestore;
  StreamSubscription? _messagesSubscription;
  // Day 6 Milestone 1: streamMessages-এর _messagesSubscription প্যাটার্নের
  // পুনরাবৃত্তি — typing স্ট্রিম বন্ধ হলে cleanup-এর জন্য।
  StreamSubscription? _typingSubscription;

  ChatRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.firestore,
  });

  @override
  String generateDirectChatId({required String uidA, required String uidB}) {
    final sorted = [uidA, uidB]..sort();
    return 'direct_${sorted[0]}_${sorted[1]}';
  }

  @override
  Future<void> ensureDirectChatExists({
    required String chatId,
    required String uidA,
    required String uidB,
  }) async {
    final chatRef = firestore.collection('chats').doc(chatId);
    final snapshot = await chatRef.get();
    if (snapshot.exists) return;

    // participantIds is the field ChatListRepositoryImpl's
    // `arrayContains` query depends on — this is the one field that was
    // never being written anywhere for 1:1 chats before this fix.
    await chatRef.set({
      'participantIds': [uidA, uidB],
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': '',
      'unreadCount': {uidA: 0, uidB: 0},
    });
  }

  @override
  String generateMessageId(String chatId) {
    // GroupRepositoryImpl.generateMessageId-এর প্যাটার্নের হুবহু পুনরাবৃত্তি —
    // শুধু একটি Firestore auto-id reserve করে, কোনো write হয় না।
    return firestore.collection('chats').doc(chatId).collection('messages').doc().id;
  }

  @override
  Future<void> sendMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
  }) async {
    return _persistMessage(
      chatId: chatId,
      senderId: senderId,
      lastMessagePreview: text,
      model: MessageModel(
        messageId: messageId,
        chatId: chatId,
        senderId: senderId,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
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
  }) async {
    return _persistMessage(
      chatId: chatId,
      senderId: senderId,
      lastMessagePreview: text.isNotEmpty ? text : _lastMessagePreviewFor(type, fileName),
      model: MessageModel(
        messageId: messageId,
        chatId: chatId,
        senderId: senderId,
        text: text,
        createdAt: DateTime.now(),
        type: type,
        mediaUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
        mimeType: mimeType,
        durationMs: durationMs,
        width: width,
        height: height,
        waveform: waveform,
      ),
    );
  }

  @override
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
  }) async {
    // Friend Alert Sounds: reuses the exact same _persistMessage helper as
    // sendMessage/sendMediaMessage — offline queueing, lastMessage/
    // unreadCount side effects, and delivery semantics are all identical,
    // not reimplemented.
    final preview = text.isNotEmpty ? text : '🔔 $alertDisplayName';
    return _persistMessage(
      chatId: chatId,
      senderId: senderId,
      lastMessagePreview: preview,
      model: MessageModel(
        messageId: messageId,
        chatId: chatId,
        senderId: senderId,
        text: text,
        createdAt: DateTime.now(),
        alertId: alertId,
        alertDisplayName: alertDisplayName,
        alertAudioUrl: alertAudioUrl,
        alertAudioChecksum: alertAudioChecksum,
        alertAudioFormat: alertAudioFormat,
        alertAudioSizeBytes: alertAudioSizeBytes,
        alertAudioDurationMs: alertAudioDurationMs,
      ),
    );
  }

  String _lastMessagePreviewFor(String type, String? fileName) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'voice':
        return 'Voice message';
      case 'file':
        return fileName ?? 'File';
      default:
        return '';
    }
  }

  Future<void> _persistMessage({
    required String chatId,
    required String senderId,
    required String lastMessagePreview,
    required MessageModel model,
  }) async {
    final messageData = model.toJson();

    // অফলাইন সিঙ্ক এবং ব্যাকঅফ ম্যানেজারের মাধ্যমে ইডিপোটেন্ট সেন্ড এক্সিকিউশন (বাগ ৪ ও ৭ ফিক্স)
    // Stability fix: এখন `return` করা হচ্ছে — OfflineQueueManager.addToQueue এখন
    // Future<void> রিটার্ন করে (আগে ছিল void), যা এই মেথডের Future-এর সাথে
    // properly propagate হয়। আগে এই `return` ছাড়াই কল হতো, ফলে `sendMessage()`
    // queue-তে টাস্ক যোগ করেই সাথে সাথে রিটার্ন করত (Firestore write আসলে
    // কখনো সফল/ব্যর্থ হয়েছে কিনা caller জানতেই পারত না — silent async failure,
    // ChatBloc-এর SendMessageEvent-এর try/catch কখনো real এরর ধরত না)।
    return OfflineQueueManager.instance.addToQueue(() async {
      await remoteDataSource.sendMessage(chatId: chatId, messageData: messageData);

      final chatRef = firestore.collection('chats').doc(chatId);

      // Day 5 Milestone 6: sendGroupMessage-এর (Day 5 M4) সমতুল্য — কাকে
      // unreadCount বাড়াতে হবে জানতে participantIds দরকার, group পাশে
      // memberUids-এর জন্য যেমন একটি extra doc read লাগে, এখানেও একই প্যাটার্নে
      // একটি extra `.get()` (কোনো নতুন query/collection নয়, বিদ্যমান
      // participantIds ফিল্ড যা ChatListRepositoryImpl আগে থেকেই পড়ে)।
      final chatSnapshot = await chatRef.get();
      final participantIds = List<String>.from(
        chatSnapshot.data()?['participantIds'] as List? ?? const [],
      );

      // Day 5 Milestone 5: group send flow-এর (sendGroupMessage, Day 5 M3)
      // সমতুল্য parent chat doc sync — message write সফল হলে
      // lastMessage/lastMessageAt(serverTimestamp)/lastMessageSenderId
      // চ্যাট ডকে merge হয়। এই ফিল্ডগুলো নতুন নয় — group পাশে ইতিমধ্যে
      // ব্যবহৃত ও ChatListItemModel.fromJson-এ আগে থেকেই parse হয় (1:1 ও
      // group উভয়ের জন্য), শুধু 1:1 পাশে এতদিন write হচ্ছিল না। কোনো নতুন
      // collection/field/schema যোগ হয়নি।
      final updateData = <String, dynamic>{
        'lastMessage': lastMessagePreview,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
      };

      // Day 5 Milestone 6: প্রেরক ছাড়া বাকি participant-দের unreadCount 1 করে
      // বাড়ানো হয়। ROOT CAUSE FIX: আগে dotted string key
      // (`updateData['unreadCount.$uid']`) ব্যবহার করা হতো, যা `.update()`-এ
      // ঠিকভাবে কাজ করে কিন্তু `set(..., SetOptions(merge:true))`-এ করে না —
      // set(merge:true) dotted string key-কে literal top-level field name
      // হিসেবে লিখে ফেলে (নেস্টেড path হিসেবে parse করে না), যা Firestore
      // rules-এর memberWritableKeys() allow-list-এ না থাকায় পুরো write-ই
      // PERMISSION_DENIED হয়ে যেত — ফলে lastMessage কখনো persist হতো না।
      // এখন প্রকৃত nested Map পাঠানো হচ্ছে — set(merge:true) নেস্টেড map field
      // deep-merge করে, তাই প্রতিটি uid-এর count আলাদাভাবে ঠিকভাবে বাড়ে এবং
      // top-level affectedKeys()-এ শুধু 'unreadCount' দেখা যায়।
      final unreadCountIncrements = <String, dynamic>{};
      for (final uid in participantIds) {
        if (uid == senderId) continue;
        unreadCountIncrements[uid] = FieldValue.increment(1);
      }
      if (unreadCountIncrements.isNotEmpty) {
        updateData['unreadCount'] = unreadCountIncrements;
      }

      await chatRef.set(updateData, SetOptions(merge: true));
    });
  }

  @override
  Future<void> resetUnreadCount({required String chatId, required String uid}) async {
    // Day 5 Milestone 6: 1:1 chat screen ওপেন হলে বর্তমান user-এর unreadCount
    // 0-এ রিসেট হয় — GroupRepositoryImpl.resetUnreadCount (Day 5 M4)-এর
    // সাথে হুবহু সামঞ্জস্যপূর্ণ প্যাটার্ন (simple dotted-path `.update()`)।
    // Stability fix: return করা হচ্ছে — নিচের সব markX/reset মেথডেও একই
    // silent-failure fix প্রযোজ্য (chat_repository_impl.dart-এর sendMessage-এর
    // ওপরের কমেন্টে ব্যাখ্যা করা হয়েছে)।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.collection('chats').doc(chatId).update({
        'unreadCount.$uid': 0,
      });
    });
  }

  @override
  Future<void> markMessageAsDelivered({
    required String chatId,
    required String messageId,
  }) async {
    // Day 6 Milestone 2 (Delivery Status): resetUnreadCount-এর মতোই simple
    // dotted-field-নয়, সরাসরি top-level `.update()` — OfflineQueueManager
    // ব্যবহার করা হলো (setTypingStatus-এর বিপরীতে) কারণ এটি ephemeral নয়:
    // একবার delivered হলে সেই তথ্য হারানো ঠিক না (typing-এর মতো stale/self-
    // correcting নয়), তাই sendMessage/resetUnreadCount-এর মতোই idempotent-retry
    // queue-এর নিরাপত্তা দরকার।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({'status': 'delivered', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  @override
  Future<void> markMessageAsRead({
    required String chatId,
    required String messageId,
  }) async {
    // Day 6 Milestone 3 (Read Receipts): markMessageAsDelivered-এর হুবহু
    // সমতুল্য প্যাটার্ন — একই doc-এর ওপর `status:'read'` `.update()`,
    // OfflineQueueManager idempotent-retry-এর ভেতরে (ephemeral নয়)।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({'status': 'read', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// CRITICAL FIX support: picks the correct sync-cursor watermark from a
  /// batch of fetched docs — uses each doc's real 'updatedAt' where present
  /// (post-migration messages), falling back to its createdAt otherwise
  /// (pre-migration messages), and returns the max across the batch.
  DateTime _maxSyncWatermark(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<MessageModel> parsed,
  ) {
    DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (var i = 0; i < docs.length; i++) {
      final rawUpdatedAt = docs[i].data()['updatedAt'];
      final updatedAt = rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : parsed[i].createdAt;
      if (updatedAt.isAfter(latest)) latest = updatedAt;
    }
    return latest;
  }

  @override
  Stream<List<MessageEntity>> streamMessages(String chatId) {
    final controller = StreamController<List<MessageEntity>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    Future<void> start() async {
      var cachedMessages = await localDataSource.getCachedMessages(chatId);
      final existingCursor = await localDataSource.getLastSyncedAt(chatId);

      // CRITICAL FIX (first-install fallback): empty cache + no cursor means
      // this device has never synced this chat at all (fresh install, new
      // device, or app data cleared) — NOT "no messages exist yet". Do one
      // explicit full history read, ordered by 'createdAt' (present on
      // every message ever written, unlike 'updatedAt' which only exists
      // going forward / after the backfill migration) so this bootstrap
      // never silently depends on that migration having run.
      if (cachedMessages.isEmpty && existingCursor == null) {
        final historySnapshot = await firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .orderBy('createdAt', descending: false)
            .get();

        final history = historySnapshot.docs
            .map((doc) => MessageModel.fromJson(doc.data(), documentId: doc.id, fallbackChatId: chatId))
            .toList();

        if (history.isNotEmpty) {
          await localDataSource.upsertMessages(chatId, history);
          await localDataSource.setLastSyncedAt(chatId, _maxSyncWatermark(historySnapshot.docs, history));
          cachedMessages = await localDataSource.getCachedMessages(chatId);
        } else {
          // Genuinely empty chat — seed the cursor so we don't re-run this
          // full scan on every open; the delta listener below picks up the
          // first real message just fine from epoch(0).
          await localDataSource.setLastSyncedAt(chatId, DateTime.fromMillisecondsSinceEpoch(0));
        }
      }

      // TASK 2 — Local Chat Storage: opening a chat always renders from the
      // on-device Hive cache first. This is a local read only — 0
      // Firestore reads for history that was already synced previously.
      if (!controller.isClosed) controller.add(cachedMessages);

      // TASK 2 — Firestore Optimization: resume from the last-synced
      // watermark (now guaranteed to be set, either from the bootstrap
      // above or a prior session) instead of re-querying the whole
      // subcollection. Every open from here on is a true delta query.
      final cursor = await localDataSource.getLastSyncedAt(chatId) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      final query = firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('updatedAt', isGreaterThan: Timestamp.fromDate(cursor))
          .orderBy('updatedAt', descending: false);

      subscription = query.snapshots().listen((snapshot) async {
        // docChanges (not snapshot.docs) — only genuinely added/modified
        // documents are processed; a query already scoped to
        // updatedAt > cursor means this is never the full history.
        if (snapshot.docChanges.isEmpty) return;

        final changed = <MessageModel>[];
        DateTime? latestUpdatedAt;
        for (final change in snapshot.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          final model = MessageModel.fromJson(
            data,
            documentId: change.doc.id,
            fallbackChatId: chatId,
          );
          changed.add(model);

          final rawUpdatedAt = data['updatedAt'];
          final updatedAt = rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : model.createdAt;
          if (latestUpdatedAt == null || updatedAt.isAfter(latestUpdatedAt)) {
            latestUpdatedAt = updatedAt;
          }
        }

        // TASK 2 — Cache Consistency: merge-write only the changed
        // messages; everything else already cached is untouched.
        await localDataSource.upsertMessages(chatId, changed);
        if (latestUpdatedAt != null) {
          await localDataSource.setLastSyncedAt(chatId, latestUpdatedAt);
        }

        if (!controller.isClosed) {
          controller.add(await localDataSource.getCachedMessages(chatId));
        }
      }, onError: (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      });

      _messagesSubscription = subscription;
    }

    start();

    // স্ট্রিম সেফটি ফিক্স: কনজিউমার লিসেনিং বন্ধ করলে ফায়ারস্টোর সাবস্ক্রিপশন
    // এবং কন্ট্রোলার স্বয়ংক্রিয়ভাবে ক্লিন-আপ হবে (মেমোরি লিক প্রতিরোধ)
    controller.onCancel = () async {
      await subscription?.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<List<MessageEntity>> loadOlderMessages({
    required String chatId,
    required DateTime beforeCreatedAt,
    int limit = 30,
  }) async {
    // FIRESTORE_SCHEMA.md ধারা ৯: pagination query pattern
    // (orderBy createdAt descending + limit), DocumentSnapshot cursor এর বদলে
    // DateTime cursor ব্যবহার করা হয়েছে যাতে Domain layer Firestore-নির্ভর না হয়।
    final snapshot = await firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .where('createdAt', isLessThan: Timestamp.fromDate(beforeCreatedAt))
        .limit(limit)
        .get();

    final olderMessages = snapshot.docs.map((doc) {
      return MessageModel.fromJson(
        doc.data(),
        documentId: doc.id,
        fallbackChatId: chatId,
      );
    }).toList();

    // ascending order-এ ফেরত দেওয়া হয়, যাতে ChatBloc-এর বিদ্যমান merge/sort
    // লজিকের সাথে সামঞ্জস্যপূর্ণ থাকে (streamMessages-ও ascending দেয়)।
    return olderMessages.reversed.toList();
  }

  @override
  Future<void> setTypingStatus({
    required String chatId,
    required String uid,
    required bool isTyping,
  }) async {
    // Day 6 Milestone 1: promoteToAdmin/demoteAdmin (GroupRepositoryImpl)-এর
    // arrayUnion/arrayRemove প্যাটার্নের 1:1-সমতুল্য পুনঃব্যবহার — নতুন কোনো
    // schema/collection নয়, শুধু `typingUserIds` নামের একটি array field।
    // OfflineQueueManager ব্যবহার করা হয়নি (interface doc-এ কারণ ব্যাখ্যা করা
    // হয়েছে) — সরাসরি `.update()`, Minimize Firestore writes অনুযায়ী প্রতি
    // কল একটি মাত্র lightweight write।
    await firestore.collection('chats').doc(chatId).update({
      'typingUserIds': isTyping
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
  }

  @override
  Stream<List<String>> streamTypingUserIds(String chatId) {
    // streamMessages/streamGroup-এর self-contained StreamController প্যাটার্ন
    // পুনরাবৃত্তি — শুধু `typingUserIds` ফিল্ড parse করে, বাকি chat doc ignore।
    final controller = StreamController<List<String>>();

    final subscription = firestore.collection('chats').doc(chatId).snapshots().listen((snapshot) {
      final data = snapshot.data();
      final typingUserIds = List<String>.from(
        data?['typingUserIds'] as List? ?? const [],
      );
      if (!controller.isClosed) controller.add(typingUserIds);
    }, onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    });

    _typingSubscription = subscription;

    controller.onCancel = () async {
      await subscription.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> close() async {
    await _messagesSubscription?.cancel();
    await _typingSubscription?.cancel();
  }
}
