import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/chat_list_item_entity.dart';
import '../../domain/repositories/chat_list_repository.dart';
import '../datasources/chat_list_local_data_source.dart';
import '../models/chat_list_item_model.dart';

class ChatListRepositoryImpl implements ChatListRepository {
  final ChatListLocalDataSource localDataSource;
  final FirebaseFirestore firestore;
  StreamSubscription? _participantChatsSubscription;
  StreamSubscription? _memberGroupsSubscription;

  ChatListRepositoryImpl({
    required this.localDataSource,
    required this.firestore,
  });

  @override
  Stream<List<ChatListItemEntity>> streamChatList(String currentUserId) {
    // লোকাল ক্যাশ থেকে তাৎক্ষণিক ডেটা রিটার্ন করা (UI জাম্প এবং অফলাইন সাপোর্ট হ্যান্ডেল করতে)
    final cachedData = localDataSource.getCachedChatList(currentUserId);

    final controller = StreamController<List<ChatListItemEntity>>();
    if (cachedData.isNotEmpty) {
      controller.add(cachedData);
    }

    // Day 5 Milestone 2: 1:1 chat (participantIds) ও group chat (memberUids)
    // দুটো আলাদা স্কিমা ব্যবহার করে বলে দুটো আলাদা Firestore query লাগে —
    // repository redesign না করে দুটো listener-এর সর্বশেষ ফলাফল client-side এ
    // merge করে একটিমাত্র combined stream হিসেবে emit করা হচ্ছে।
    List<ChatListItemModel> latestParticipantChats = [];
    List<ChatListItemModel> latestMemberGroups = [];
    bool participantChatsReady = false;
    bool memberGroupsReady = false;

    void emitMerged() {
      // দুটো স্ট্রিমেরই অন্তত একবার ডেটা আসা পর্যন্ত অপেক্ষা করা হয়, নাহলে
      // প্রথম snapshot-এ শুধু এক ধরনের chat দিয়ে আংশিক তালিকা flash হতো।
      if (!participantChatsReady || !memberGroupsReady) return;

      final combinedById = <String, ChatListItemModel>{};
      for (final chat in latestParticipantChats) {
        combinedById[chat.chatId] = chat;
      }
      for (final group in latestMemberGroups) {
        combinedById[group.chatId] = group;
      }
      final merged = combinedById.values.toList()
        ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

      // লোকাল ক্যাশে সিঙ্ক রাইট করা (এখন combined list)
      localDataSource.cacheChatList(currentUserId, merged);
      if (!controller.isClosed) {
        controller.add(merged);
      }
    }

    // FIRESTORE_SCHEMA.md ধারা ৯: 1:1 chat query pattern (অপরিবর্তিত)
    final participantSubscription = firestore
        .collection('chats')
        .where('participantIds', arrayContains: currentUserId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          latestParticipantChats = snapshot.docs
              .map((doc) => ChatListItemModel.fromJson(doc.data(), documentId: doc.id))
              .toList();
          participantChatsReady = true;
          emitMerged();
        }, onError: (error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        });

    // Day 5 Milestone 2: group chats memberUids দিয়ে identify হয়। ইচ্ছাকৃতভাবে
    // এখানে orderBy('lastMessageAt') ব্যবহার করা হয়নি — group doc-এ এই ফিল্ড
    // এখনো কখনো লেখা হয় না (createGroup-এ নেই, পৃথক pre-existing gap, এই
    // মাইলস্টোনের স্কোপের বাইরে), আর orderBy দিলে Firestore সেই ফিল্ড-বিহীন
    // group ডকুমেন্টগুলোকেই query result থেকে বাদ দিয়ে দিত। মিসিং
    // lastMessageAt ChatListItemModel.fromJson-এ আগে থেকেই DateTime.now()
    // ডিফল্ট করে, তাই merged list-এর client-side sort-এ কোনো সমস্যা হয় না।
    final memberSubscription = firestore
        .collection('chats')
        .where('memberUids', arrayContains: currentUserId)
        .snapshots()
        .listen((snapshot) {
          latestMemberGroups = snapshot.docs
              .map((doc) => ChatListItemModel.fromJson(doc.data(), documentId: doc.id))
              .toList();
          memberGroupsReady = true;
          emitMerged();
        }, onError: (error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        });

    _participantChatsSubscription = participantSubscription;
    _memberGroupsSubscription = memberSubscription;

    // স্ট্রিম সেফটি ফিক্স: কনজিউমার লিসেনিং বন্ধ করলে দুটো ফায়ারস্টোর
    // সাবস্ক্রিপশন এবং কন্ট্রোলার স্বয়ংক্রিয়ভাবে ক্লিন-আপ হবে (মেমোরি লিক প্রতিরোধ)
    controller.onCancel = () async {
      await participantSubscription.cancel();
      await memberSubscription.cancel();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  @override
  Future<void> close() async {
    await _participantChatsSubscription?.cancel();
    await _memberGroupsSubscription?.cancel();
  }
}
