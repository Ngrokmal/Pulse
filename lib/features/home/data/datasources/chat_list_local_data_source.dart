import '../../../../core/services/local_db_service.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../domain/entities/chat_list_item_entity.dart';
import '../models/chat_list_item_model.dart';

abstract class ChatListLocalDataSource {
  Future<void> cacheChatList(String uid, List<ChatListItemEntity> chats);

  Future<List<ChatListItemEntity>> getCachedChatList(String uid);

  Future<DateTime?> getDirectChatListSyncedAt(String uid);

  Future<void> setDirectChatListSyncedAt(String uid, DateTime time);

  Future<void> setUnreadCount(String uid, String chatId, int count);

  Future<Set<String>?> getCachedFriendSupabaseIds(String uid);

  Future<void> setCachedFriendSupabaseIds(String uid, Set<String> ids);

  Future<void> deleteCachedFriendSupabaseIds(String uid);
}

class ChatListLocalDataSourceImpl implements ChatListLocalDataSource {
  String _boxName(String uid) => 'home_chat_list_$uid';

  @override
  Future<void> cacheChatList(String uid, List<ChatListItemEntity> chats) async {
    final box = await LocalDbService.homeChatListBox(_boxName(uid));
    await box.clear();
    for (final chat in chats) {
      final model = chat is ChatListItemModel ? chat : ChatListItemModel(
        chatId: chat.chatId,
        participantIds: chat.participantIds,
        lastMessage: chat.lastMessage,
        lastMessageAt: chat.lastMessageAt,
        lastMessageSenderId: chat.lastMessageSenderId,
        unreadCount: chat.unreadCount,
        groupPhotoUrl: chat.groupPhotoUrl,
        isGroup: chat.isGroup,
        name: chat.name,
      );
      await box.put(model.chatId, model.toCacheJson());
    }
  }

  @override
  Future<List<ChatListItemEntity>> getCachedChatList(String uid) async {
    final box = await LocalDbService.homeChatListBox(_boxName(uid));
    return box.values.map((raw) => ChatListItemModel.fromCacheJson(Map<String, dynamic>.from(raw))).toList();
  }

  @override
  Future<DateTime?> getDirectChatListSyncedAt(String uid) {
    return SyncEngine.instance.getCursor('homeChatListDirectSyncedAt_$uid');
  }

  @override
  Future<void> setDirectChatListSyncedAt(String uid, DateTime time) {
    return SyncEngine.instance.setCursor('homeChatListDirectSyncedAt_$uid', time);
  }

  @override
  Future<void> setUnreadCount(String uid, String chatId, int count) async {
    final box = await LocalDbService.homeChatListBox(_boxName(uid));
    final raw = box.get(chatId);
    if (raw == null) return;
    final model = ChatListItemModel.fromCacheJson(Map<String, dynamic>.from(raw));
    final patchedUnread = Map<String, int>.from(model.unreadCount)..[uid] = count;
    final patched = model.copyWith(unreadCount: patchedUnread);
    await box.put(chatId, patched.toCacheJson());
  }

  @override
  Future<Set<String>?> getCachedFriendSupabaseIds(String uid) async {
    final box = await LocalDbService.syncMetaBox();
    final raw = box.get('homeChatListFriendIds_$uid');
    if (raw == null) return null;
    return Set<String>.from(List<dynamic>.from(raw as List));
  }

  @override
  Future<void> setCachedFriendSupabaseIds(String uid, Set<String> ids) async {
    final box = await LocalDbService.syncMetaBox();
    await box.put('homeChatListFriendIds_$uid', ids.toList());
  }

  @override
  Future<void> deleteCachedFriendSupabaseIds(String uid) async {
    final box = await LocalDbService.syncMetaBox();
    await box.delete('homeChatListFriendIds_$uid');
  }
}
