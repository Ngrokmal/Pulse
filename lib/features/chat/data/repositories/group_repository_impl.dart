import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/network/offline_queue.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/group_repository.dart';
import '../datasources/chat_local_data_source.dart';
import '../models/message_model.dart';

class GroupRepositoryImpl implements GroupRepository {
  final FirebaseFirestore firestore;
  final ChatLocalDataSource localDataSource;
  StreamSubscription? _groupMessagesSubscription;
  // Day 6 Milestone 1: ChatRepositoryImpl-এর _typingSubscription-এর group-সমতুল্য।
  StreamSubscription? _typingSubscription;

  GroupRepositoryImpl({required this.firestore, required this.localDataSource});

  @override
  String generateGroupId() {
    // শুধু একটি ID reserve করা হয় (কোনো write হয় না) — 1:1 চ্যাটের deterministic
    // ID-এর বিপরীতে, group ID auto-generated হওয়াই ইচ্ছাকৃত (GROUP_CHAT_ALGORITHM.md ধারা ১)।
    return firestore.collection('chats').doc().id;
  }

  @override
  Future<void> createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    required List<String> initialMembers,
  }) async {
    final batch = firestore.batch();
    
    // রুল ২: মেটাডেটা ডকুমেন্ট এবং কস্ট অপ্টিমাইজড মেম্বারশিপ ট্র্যাকিং
    final groupRef = firestore.collection('chats').doc(groupId);
    batch.set(groupRef, {
      'groupId': groupId,
      'name': name,
      'creatorId': creatorId,
      'memberUids': initialMembers, // রুল ১ ও বাগ ৯: ইন-ডকুমেন্ট অ্যারে ফর সিকিউরিটি চেক অপ্টিমাইজেশন
      'adminIds': [creatorId], // Milestone 5: creator সবসময় প্রথম admin
      'createdAt': FieldValue.serverTimestamp(),
    });

    // রুল ২ ও ৮: স্কেলেবিলিটি এবং ১MB লিমিট এড়াতে সাব-কালেকশন মেম্বার লিস্ট
    for (final uid in initialMembers) {
      final memberRef = groupRef.collection('members').doc(uid);
      batch.set(memberRef, {
        'uid': uid,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  @override
  Stream<GroupEntity> streamGroup(String groupId) {
    // streamGroupMessages-এর মতোই self-contained StreamController/subscription
    // প্যাটার্ন — Group Info স্ক্রিন এই একটি স্ট্রিম থেকেই group metadata এবং
    // Member List (cachedMemberUids) দুটোই পায়।
    final controller = StreamController<GroupEntity>();

    final subscription = firestore.collection('chats').doc(groupId).snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        if (!controller.isClosed) {
          controller.addError(StateError('Group not found: $groupId'));
        }
        return;
      }

      final Timestamp? timestamp = data['createdAt'] as Timestamp?;
      final group = GroupEntity(
        groupId: data['groupId'] as String? ?? snapshot.id,
        name: data['name'] as String? ?? '',
        creatorId: data['creatorId'] as String? ?? '',
        cachedMemberUids: List<String>.from(data['memberUids'] as List? ?? const []),
        adminIds: List<String>.from(data['adminIds'] as List? ?? const []), // Milestone 5, খালি হলে GroupEntity.isAdmin creator-fallback করে
        createdAt: timestamp != null ? timestamp.toDate() : DateTime.now(),
        groupPhotoUrl: data['groupPhotoUrl'] as String?, // Milestone 6, না থাকলে null (পুরনো doc/no-photo group)
        groupPhotoPublicId: data['groupPhotoPublicId'] as String?,
      );

      if (!controller.isClosed) controller.add(group);
    }, onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    });

    controller.onCancel = () async {
      await subscription.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> addMember({required String groupId, required String uid}) async {
    // Stability fix: return করা হচ্ছে (silent-failure fix, chat_repository_impl.dart
    // sendMessage-এর কমেন্টে বিস্তারিত ব্যাখ্যা করা হয়েছে — OfflineQueueManager.addToQueue
    // এখন Future<void> রিটার্ন করে, নিচের সব GroupRepositoryImpl মেথডে একই fix প্রয়োগ)।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.runTransaction((transaction) async {
        final groupRef = firestore.collection('chats').doc(groupId);
        final memberRef = groupRef.collection('members').doc(uid);

        transaction.update(groupRef, {
          'memberUids': FieldValue.arrayUnion([uid]),
        });
        transaction.set(memberRef, {
          'uid': uid,
          'joinedAt': FieldValue.serverTimestamp(),
        });
      });
    });
  }

  @override
  Future<void> removeMember({required String groupId, required String uid}) async {
    // addMember-এর হুবহু বিপরীত প্যাটার্ন: একই transaction-এ members sub-collection
    // ডকুমেন্ট ডিলিট + cached memberUids array থেকে arrayRemove, যাতে দুটো সবসময়
    // sync থাকে। admin-only gating GroupInfoBloc-এ হয় (Milestone 5) — এই মেথড
    // নিজে permission চেক করে না, শুধু storage-লেয়ার mutation।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.runTransaction((transaction) async {
        final groupRef = firestore.collection('chats').doc(groupId);
        final memberRef = groupRef.collection('members').doc(uid);

        transaction.update(groupRef, {
          'memberUids': FieldValue.arrayRemove([uid]),
          'adminIds': FieldValue.arrayRemove([uid]), // Milestone 5: removed member আর admin থাকতে পারে না
        });
        transaction.delete(memberRef);
      });
    });
  }

  @override
  Future<void> leaveGroup({required String groupId, required String uid}) async {
    // removeMember-এর মতোই OfflineQueueManager প্যাটার্ন, কিন্তু conditional
    // (last-member delete / creator-transfer) লজিকের জন্য প্রথমে transaction-এর
    // ভেতরে group document read করা হয় (transaction.get) — addMember/removeMember
    // ব্লাইন্ড arrayUnion/arrayRemove করে, এখানে read-then-decide প্রয়োজন।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.runTransaction((transaction) async {
        final groupRef = firestore.collection('chats').doc(groupId);
        final memberRef = groupRef.collection('members').doc(uid);

        final snapshot = await transaction.get(groupRef);
        final data = snapshot.data();
        if (data == null) {
          // group ইতিমধ্যেই ডিলিট হয়ে গেছে (অন্য ডিভাইস/রিট্রাই থেকে) — idempotent no-op।
          return;
        }

        final currentMembers = List<String>.from(data['memberUids'] as List? ?? const []);
        final remainingMembers = currentMembers.where((m) => m != uid).toList();
        final currentCreatorId = data['creatorId'] as String? ?? '';
        final currentAdminIds = List<String>.from(data['adminIds'] as List? ?? const []);

        if (remainingMembers.isEmpty) {
          // শেষ member চলে গেলে পুরো group document ডিলিট। NOTE: messages ও
          // members sub-collection client-side batch/transaction দিয়ে recursively
          // ডিলিট করা যায় না (Cloud Function ছাড়া) — জানা সীমাবদ্ধতা, নিচে ধারা ৫ দেখুন।
          transaction.delete(memberRef);
          transaction.delete(groupRef);
          return;
        }

        final updates = <String, dynamic>{
          'memberUids': FieldValue.arrayRemove([uid]),
          'adminIds': FieldValue.arrayRemove([uid]), // Milestone 5: leaving user আর admin থাকতে পারে না
        };

        // Creator transfer: leaving user creator হলে ও group survive করলে,
        // pre-removal memberUids order-এর পরবর্তী remaining uid deterministically
        // নতুন creator হিসেবে promote হয়। Milestone 5: নতুন creator adminIds-এও
        // যোগ হয় (creator ইতিমধ্যেই GroupEntity.isAdmin-এ implicit admin, কিন্তু
        // explicit adminIds array-ও sync রাখা হলো যাতে admin list UI-তে সঠিক দেখায়)।
        // দুটো arrayUnion/arrayRemove একই ফিল্ডে (adminIds) একসাথে সেট করা যায় না
        // বলে creator-transfer হলে পুরো adminIds নতুন করে গণনা করা হচ্ছে।
        if (uid == currentCreatorId) {
          final newCreatorId = remainingMembers.first;
          updates['creatorId'] = newCreatorId;
          final newAdminIds = currentAdminIds.where((a) => a != uid).toSet();
          newAdminIds.add(newCreatorId);
          updates['adminIds'] = newAdminIds.toList();
        }

        transaction.update(groupRef, updates);
        transaction.delete(memberRef);
      });
    });
  }

  @override
  Future<void> promoteToAdmin({required String groupId, required String uid}) async {
    // AddMemberRequested-এর মতো simple arrayUnion — কোনো conditional read
    // দরকার নেই কারণ permission/last-admin গার্ড GroupInfoBloc-এ হয়।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.collection('chats').doc(groupId).update({
        'adminIds': FieldValue.arrayUnion([uid]),
      });
    });
  }

  @override
  Future<void> demoteAdmin({required String groupId, required String uid}) async {
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.collection('chats').doc(groupId).update({
        'adminIds': FieldValue.arrayRemove([uid]),
      });
    });
  }

  @override
  Future<void> updateGroupName({required String groupId, required String name}) async {
    // promoteToAdmin/demoteAdmin-এর মতোই simple field update — কোনো conditional
    // read দরকার নেই, admin-permission গার্ড GroupInfoBloc-এ হয়।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.collection('chats').doc(groupId).update({
        'name': name,
      });
    });
  }

  @override
  Future<void> updateGroupPhoto({
    required String groupId,
    required String photoUrl,
    required String publicId,
  }) async {
    // পুরনো Cloudinary asset ডিলিট এখানে হয় না (এই মেথড শুধু Firestore-লেয়ার
    // mutation) — GroupInfoBloc নতুন photo persist হওয়ার *পরে* MediaRepository
    // দিয়ে পুরনো publicId আলাদাভাবে ডিলিট করে, যাতে নতুন ছবি সবসময় আগে live হয়।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.collection('chats').doc(groupId).update({
        'groupPhotoUrl': photoUrl,
        'groupPhotoPublicId': publicId,
      });
    });
  }

  @override
  String generateMessageId(String groupId) {
    // GroupRepositoryImpl-এ কোনো আলাদা remoteDataSource নেই (ChatRepositoryImpl-এর
    // থেকে ভিন্ন), তাই সরাসরি firestore auto-id ব্যবহার করা হয় (generateGroupId-এর
    // মতোই প্যাটার্ন)।
    return firestore.collection('chats').doc(groupId).collection('messages').doc().id;
  }

  @override
  Future<void> sendGroupMessage({
    required String groupId,
    required String messageId,
    required String senderId,
    required String text,
  }) async {
    // MessageModel পুনঃব্যবহার করা হয়েছে — 1:1 ও group message-এর Firestore schema
    // অভিন্ন (chats/{id}/messages), তাই আলাদা GroupMessageModel তৈরির প্রয়োজন নেই।
    final messageData = MessageModel(
      messageId: messageId,
      chatId: groupId,
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
    ).toJson();

    // ChatRepositoryImpl.sendMessage-এর মতোই অফলাইন সেফ ইডিপোটেন্ট সেন্ড এক্সিকিউশন
    return OfflineQueueManager.instance.addToQueue(() async {
      final groupRef = firestore.collection('chats').doc(groupId);

      // Day 5 Milestone 4: unreadCount বাড়ানোর জন্য কাকে বাড়াতে হবে জানতে
      // memberUids দরকার — GroupEntity.cachedMemberUids-এর মতোই এই একই
      // in-document array read করা হয় (কোনো নতুন query/collection নয়)।
      final groupSnapshot = await groupRef.get();
      final memberUids = List<String>.from(
        groupSnapshot.data()?['memberUids'] as List? ?? const [],
      );

      // Day 5 Milestone 3: message write ও parent group doc-এর lastMessage/
      // lastMessageAt/lastMessageSenderId আপডেট একসাথে batch-এ করা হয়, যাতে
      // Home chat list query (FIRESTORE_SCHEMA.md ধারা ৯)-এর জন্য প্রয়োজনীয়
      // ফিল্ডগুলো message write-এর সাথেই atomically sync থাকে (partial-failure
      // এড়াতে দুটো আলাদা write-এর বদলে একটি batch)। কোনো নতুন কালেকশন/ফিল্ড নাম
      // যোগ হয়নি — lastMessage/lastMessageAt/lastMessageSenderId ইতিমধ্যেই 1:1
      // chat doc-এ ও ChatListItemModel-এ ব্যবহৃত বিদ্যমান ফিল্ড।
      final batch = firestore.batch();

      final messageRef = groupRef.collection('messages').doc(messageId);
      batch.set(messageRef, messageData);

      final updateData = <String, dynamic>{
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': senderId,
      };

      // Day 5 Milestone 4: প্রেরক ছাড়া বাকি সব member-এর unreadCount 1 করে
      // বাড়ানো হয়। ROOT CAUSE FIX: dotted string key
      // (`updateData['unreadCount.$uid']`) `set(..., SetOptions(merge:true))`
      // এর সাথে ব্যবহার করলে সেটা literal top-level field name হিসেবে লেখা
      // হয় (nested path হিসেবে parse হয় না — শুধু `.update()` তা করে), যা
      // Firestore rules-এর memberWritableKeys() allow-list ভঙ্গ করে পুরো
      // write PERMISSION_DENIED করে দিত। এখন প্রকৃত nested Map পাঠানো হচ্ছে —
      // set(merge:true) সেটা ঠিকভাবে deep-merge করে।
      final unreadCountIncrements = <String, dynamic>{};
      for (final uid in memberUids) {
        if (uid == senderId) continue;
        unreadCountIncrements[uid] = FieldValue.increment(1);
      }
      if (unreadCountIncrements.isNotEmpty) {
        updateData['unreadCount'] = unreadCountIncrements;
      }

      batch.set(groupRef, updateData, SetOptions(merge: true));

      await batch.commit();
    });
  }

  @override
  Future<void> resetUnreadCount({
    required String groupId,
    required String uid,
  }) async {
    // Day 5 Milestone 4: group chat screen ওপেন হলে বর্তমান user-এর unreadCount
    // 0-এ রিসেট হয় — promoteToAdmin/demoteAdmin-এর মতোই simple dotted-path
    // update, কোনো নতুন collection/read দরকার নেই।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore.collection('chats').doc(groupId).update({
        'unreadCount.$uid': 0,
      });
    });
  }

  @override
  Future<void> markMessageAsRead({
    required String groupId,
    required String messageId,
    required String uid,
  }) async {
    // অফলাইন সেফ ইডিপোটেন্ট রিড-রিসিপ্ট আপডেট পলিসি — per-uid receipts
    // sub-collection write (পূর্ব-বিদ্যমান, অপরিবর্তিত)।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .doc(messageId)
          .collection('receipts')
          .doc(uid)
          .set({
            'readAt': FieldValue.serverTimestamp(),
          });

      // Day 6 Milestone 3 (Read Receipts): markMessageAsDelivered-এর
      // per-member-granular-নয় সিদ্ধান্তের সাথে সামঞ্জস্যপূর্ণ — UI-তে
      // একটিমাত্র shared `status` ফিল্ড দিয়ে ✓✓→● দেখানো হয় (receipts
      // sub-collection-টি per-uid granular ডেটা হিসেবে থেকে যায়, ভবিষ্যতে
      // per-recipient read UI দরকার হলে ব্যবহারযোগ্য, কিন্তু বর্তমান UI
      // রিকোয়ারমেন্ট অনুযায়ী প্রথম non-sender read-ই যথেষ্ট — WhatsApp-এর
      // single-tick→double-tick মডেলের মতোই, per-recipient নয়)।
      await firestore
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .doc(messageId)
          .update({'status': 'read', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  @override
  Future<void> markMessageAsDelivered({
    required String groupId,
    required String messageId,
  }) async {
    // ChatRepositoryImpl.markMessageAsDelivered-এর হুবহু সমতুল্য (একই field
    // name, একই OfflineQueueManager idempotent-retry যুক্তি)।
    return OfflineQueueManager.instance.addToQueue(() async {
      await firestore
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .doc(messageId)
          .update({'status': 'delivered', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// CRITICAL FIX support (group side) — see ChatRepositoryImpl's
  /// _maxSyncWatermark for the full explanation.
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
  Stream<List<MessageEntity>> streamGroupMessages(String groupId) {
    final controller = StreamController<List<MessageEntity>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;

    Future<void> start() async {
      var cachedMessages = await localDataSource.getCachedMessages(groupId);
      final existingCursor = await localDataSource.getLastSyncedAt(groupId);

      // CRITICAL FIX (first-install fallback) — identical reasoning as
      // ChatRepositoryImpl.streamMessages: empty cache + no cursor means
      // this device never synced this group chat, not "no messages exist".
      if (cachedMessages.isEmpty && existingCursor == null) {
        final historySnapshot = await firestore
            .collection('chats')
            .doc(groupId)
            .collection('messages')
            .orderBy('createdAt', descending: false)
            .get();

        final history = historySnapshot.docs
            .map((doc) => MessageModel.fromJson(doc.data(), documentId: doc.id, fallbackChatId: groupId))
            .toList();

        if (history.isNotEmpty) {
          await localDataSource.upsertMessages(groupId, history);
          await localDataSource.setLastSyncedAt(groupId, _maxSyncWatermark(historySnapshot.docs, history));
          cachedMessages = await localDataSource.getCachedMessages(groupId);
        } else {
          await localDataSource.setLastSyncedAt(groupId, DateTime.fromMillisecondsSinceEpoch(0));
        }
      }

      // TASK 2 — Local Chat Storage: same as 1:1 chats, render from the
      // local cache first — 0 Firestore reads to open a group chat.
      if (!controller.isClosed) controller.add(cachedMessages);

      final cursor = await localDataSource.getLastSyncedAt(groupId) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      final query = firestore
          .collection('chats')
          .doc(groupId)
          .collection('messages')
          .where('updatedAt', isGreaterThan: Timestamp.fromDate(cursor))
          .orderBy('updatedAt', descending: false);

      subscription = query.snapshots().listen((snapshot) async {
        if (snapshot.docChanges.isEmpty) return;

        final changed = <MessageModel>[];
        DateTime? latestUpdatedAt;
        for (final change in snapshot.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          final model = MessageModel.fromJson(
            data,
            documentId: change.doc.id,
            fallbackChatId: groupId,
          );
          changed.add(model);

          final rawUpdatedAt = data['updatedAt'];
          final updatedAt = rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : model.createdAt;
          if (latestUpdatedAt == null || updatedAt.isAfter(latestUpdatedAt)) {
            latestUpdatedAt = updatedAt;
          }
        }

        await localDataSource.upsertMessages(groupId, changed);
        if (latestUpdatedAt != null) {
          await localDataSource.setLastSyncedAt(groupId, latestUpdatedAt);
        }

        if (!controller.isClosed) {
          controller.add(await localDataSource.getCachedMessages(groupId));
        }
      }, onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      });

      _groupMessagesSubscription = subscription;
    }

    start();

    controller.onCancel = () async {
      await subscription?.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> setTypingStatus({
    required String groupId,
    required String uid,
    required bool isTyping,
  }) async {
    // ChatRepositoryImpl.setTypingStatus-এর হুবহু সমতুল্য (একই field name,
    // একই arrayUnion/arrayRemove প্যাটার্ন, একই OfflineQueueManager-বাদ-দেওয়ার যুক্তি)।
    await firestore.collection('chats').doc(groupId).update({
      'typingUserIds': isTyping
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
  }

  @override
  Stream<List<String>> streamTypingUserIds(String groupId) {
    // ChatRepositoryImpl.streamTypingUserIds-এর হুবহু সমতুল্য।
    final controller = StreamController<List<String>>();

    final subscription = firestore.collection('chats').doc(groupId).snapshots().listen((snapshot) {
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
    await _groupMessagesSubscription?.cancel();
    await _typingSubscription?.cancel();
  }
}
