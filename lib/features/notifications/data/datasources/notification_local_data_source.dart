import '../../../../core/services/local_db_service.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../domain/entities/notification_item_entity.dart';
import '../models/notification_item_model.dart';

abstract class NotificationLocalDataSource {
  Future<List<NotificationItemEntity>> getCachedNotifications(String uid);

  Future<void> upsertNotifications(String uid, List<NotificationItemEntity> notifications);

  Future<void> deleteCached(String uid, String notificationId);

  Future<void> markCachedAsRead(String uid, String notificationId);

  Future<void> markAllCachedAsRead(String uid);

  Future<DateTime?> getLastSyncedAt(String uid);

  Future<void> setLastSyncedAt(String uid, DateTime time);
}

class NotificationLocalDataSourceImpl implements NotificationLocalDataSource {
  @override
  Future<List<NotificationItemEntity>> getCachedNotifications(String uid) async {
    final box = await LocalDbService.notificationsBox(uid);
    final items = box.values.map((raw) => NotificationItemModel.fromCacheJson(Map<String, dynamic>.from(raw))).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<void> upsertNotifications(String uid, List<NotificationItemEntity> notifications) async {
    if (notifications.isEmpty) return;
    final box = await LocalDbService.notificationsBox(uid);
    for (final item in notifications) {
      final model = item is NotificationItemModel ? item : NotificationItemModel.fromEntity(item);
      await box.put(model.id, model.toCacheJson());
    }
  }

  @override
  Future<void> deleteCached(String uid, String notificationId) async {
    final box = await LocalDbService.notificationsBox(uid);
    await box.delete(notificationId);
  }

  @override
  Future<void> markCachedAsRead(String uid, String notificationId) async {
    final box = await LocalDbService.notificationsBox(uid);
    final raw = box.get(notificationId);
    if (raw == null) return;
    final model = NotificationItemModel.fromCacheJson(Map<String, dynamic>.from(raw));
    await box.put(notificationId, NotificationItemModel(
      id: model.id,
      type: model.type,
      title: model.title,
      body: model.body,
      data: model.data,
      chatId: model.chatId,
      messageId: model.messageId,
      isRead: true,
      createdAt: model.createdAt,
    ).toCacheJson());
  }

  @override
  Future<void> markAllCachedAsRead(String uid) async {
    final box = await LocalDbService.notificationsBox(uid);
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final model = NotificationItemModel.fromCacheJson(Map<String, dynamic>.from(raw));
      if (model.isRead) continue;
      await box.put(key, NotificationItemModel(
        id: model.id,
        type: model.type,
        title: model.title,
        body: model.body,
        data: model.data,
        chatId: model.chatId,
        messageId: model.messageId,
        isRead: true,
        createdAt: model.createdAt,
      ).toCacheJson());
    }
  }

  @override
  Future<DateTime?> getLastSyncedAt(String uid) {
    return SyncEngine.instance.getCursor('notificationsSyncedAt_$uid');
  }

  @override
  Future<void> setLastSyncedAt(String uid, DateTime time) {
    return SyncEngine.instance.setCursor('notificationsSyncedAt_$uid', time);
  }
}
