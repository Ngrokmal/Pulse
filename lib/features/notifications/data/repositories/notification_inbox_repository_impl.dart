import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/offline_queue.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../domain/entities/notification_item_entity.dart';
import '../../domain/repositories/notification_inbox_repository.dart';
import '../datasources/notification_local_data_source.dart';
import '../datasources/notification_remote_data_source.dart';
import '../models/notification_item_model.dart';

class NotificationInboxRepositoryImpl implements NotificationInboxRepository {
  final NotificationLocalDataSource localDataSource;
  final NotificationRemoteDataSource remoteDataSource;
  final SupabaseClient supabase;

  NotificationInboxRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
    required this.supabase,
  });

  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, RealtimeChannel> _unreadChannels = {};

  Future<String> _resolveUid(String uid) {
    return UserIdBridge.resolve(uid, currentSupabaseUserId: supabase.auth.currentUser?.id);
  }

  @override
  Stream<List<NotificationItemEntity>> streamNotifications(String uid) {
    final controller = StreamController<List<NotificationItemEntity>>();
    List<NotificationItemModel> current = [];
    bool cancelled = false;
    String? myUuid;

    void emit() {
      current.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      localDataSource.upsertNotifications(uid, current);
      if (!controller.isClosed) controller.add(List<NotificationItemEntity>.from(current));
    }

    Future<void> runDelta(String recipientId) async {
      await SyncEngine.instance.runDelta<Map<String, dynamic>>(
        getCursor: () => localDataSource.getLastSyncedAt(uid),
        setCursor: (time) => localDataSource.setLastSyncedAt(uid, time),
        fetchChanges: (since) => remoteDataSource.fetchChangedNotifications(recipientId: recipientId, since: since),
        updatedAtOf: (row) {
          final raw = row['updated_at'] ?? row['created_at'];
          return raw is String ? DateTime.parse(raw).toLocal() : DateTime.now();
        },
        isTombstone: (row) => row['deleted_at'] != null,
        onTombstone: (row) async {
          final id = row['id'] as String?;
          if (id == null) return;
          current.removeWhere((n) => n.id == id);
          await localDataSource.deleteCached(uid, id);
        },
        onUpsert: (row) async {
          final model = NotificationItemModel.fromSupabaseRow(row);
          final idx = current.indexWhere((n) => n.id == model.id);
          if (idx >= 0) {
            current[idx] = model;
          } else {
            current.add(model);
          }
        },
      );
      emit();
    }

    void applyRealtimeChange(PostgresChangePayload payload) {
      if (payload.eventType == PostgresChangeEvent.delete) {
        final oldId = payload.oldRecord['id'] as String?;
        if (oldId == null) return;
        current.removeWhere((n) => n.id == oldId);
        localDataSource.deleteCached(uid, oldId);
        emit();
        return;
      }
      final newRecord = payload.newRecord;
      if (newRecord['deleted_at'] != null) {
        final id = newRecord['id'] as String?;
        if (id == null) return;
        current.removeWhere((n) => n.id == id);
        localDataSource.deleteCached(uid, id);
        emit();
        return;
      }
      final model = NotificationItemModel.fromSupabaseRow(newRecord);
      final idx = current.indexWhere((n) => n.id == model.id);
      if (idx >= 0) {
        current[idx] = model;
      } else {
        current.add(model);
      }
      emit();
    }

    Future<void> start() async {
      final cached = await localDataSource.getCachedNotifications(uid);
      current = cached.whereType<NotificationItemModel>().toList();
      if (current.isNotEmpty && !controller.isClosed) {
        controller.add(List<NotificationItemEntity>.from(current));
      }
      if (cancelled) return;

      final String resolvedUuid;
      try {
        resolvedUuid = await _resolveUid(uid);
      } catch (_) {
        return;
      }
      if (cancelled) return;
      myUuid = resolvedUuid;

      final channel = supabase
          .channel('notifications_$resolvedUuid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: resolvedUuid,
            ),
            callback: applyRealtimeChange,
          );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          runDelta(resolvedUuid);
        }
        if (error != null && !controller.isClosed) {
          controller.addError(error);
        }
      });

      if (cancelled) {
        await supabase.removeChannel(channel);
        return;
      }
      final existing = _channels[resolvedUuid];
      if (existing != null) await supabase.removeChannel(existing);
      _channels[resolvedUuid] = channel;
    }

    start();

    controller.onCancel = () async {
      cancelled = true;
      final uuid = myUuid;
      if (uuid != null) {
        final channel = _channels[uuid];
        if (channel != null) {
          await supabase.removeChannel(channel);
          if (identical(_channels[uuid], channel)) _channels.remove(uuid);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Stream<int> streamUnreadCount(String uid) {
    final controller = StreamController<int>();
    bool cancelled = false;
    String? myUuid;

    Future<void> emitCount(String recipientId) async {
      final cached = await localDataSource.getCachedNotifications(uid);
      if (!controller.isClosed) {
        controller.add(cached.where((n) => !n.isRead).length);
      }
      try {
        final res = await supabase
            .from('notifications')
            .select('id')
            .eq('recipient_id', recipientId)
            .eq('is_read', false)
            .count(CountOption.exact);
        if (!controller.isClosed) controller.add(res.count);
      } catch (_) {
      }
    }

    Future<void> start() async {
      final String resolvedUuid;
      try {
        resolvedUuid = await _resolveUid(uid);
      } catch (_) {
        final cached = await localDataSource.getCachedNotifications(uid);
        if (!controller.isClosed) controller.add(cached.where((n) => !n.isRead).length);
        return;
      }
      if (cancelled) return;
      myUuid = resolvedUuid;

      final channel = supabase
          .channel('notifications_unread_$resolvedUuid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'recipient_id',
              value: resolvedUuid,
            ),
            callback: (_) => emitCount(resolvedUuid),
          );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) emitCount(resolvedUuid);
        if (error != null && !controller.isClosed) controller.addError(error);
      });

      if (cancelled) {
        await supabase.removeChannel(channel);
        return;
      }
      final existing = _unreadChannels[resolvedUuid];
      if (existing != null) await supabase.removeChannel(existing);
      _unreadChannels[resolvedUuid] = channel;
    }

    start();

    controller.onCancel = () async {
      cancelled = true;
      final uuid = myUuid;
      if (uuid != null) {
        final channel = _unreadChannels[uuid];
        if (channel != null) {
          await supabase.removeChannel(channel);
          if (identical(_unreadChannels[uuid], channel)) _unreadChannels.remove(uuid);
        }
      }
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Future<void> markAsRead({required String uid, required String notificationId}) {
    return OfflineQueueManager.instance.addToQueue(() async {
      await localDataSource.markCachedAsRead(uid, notificationId);
      await remoteDataSource.markAsRead(notificationId: notificationId);
    });
  }

  @override
  Future<void> markAllAsRead(String uid) {
    return OfflineQueueManager.instance.addToQueue(() async {
      await localDataSource.markAllCachedAsRead(uid);
      final recipientId = await _resolveUid(uid);
      await remoteDataSource.markAllAsRead(recipientId: recipientId);
    });
  }

  static const String deleteNotificationOpType = 'notifications.deleteNotification';

  @override
  Future<void> deleteNotification({required String uid, required String notificationId}) async {
    await localDataSource.deleteCached(uid, notificationId);
    await OfflineQueueManager.instance.addPersistentTask(
      opType: deleteNotificationOpType,
      taskId: '$deleteNotificationOpType:$notificationId',
      payload: {'notificationId': notificationId},
    );
  }

  void registerOfflineQueueHandlers() {
    OfflineQueueManager.instance.registerHandler(deleteNotificationOpType, (payload) {
      return remoteDataSource.deleteNotification(notificationId: payload['notificationId'] as String);
    });
  }

  @override
  Future<void> close() async {
    for (final channel in _channels.values) {
      await supabase.removeChannel(channel);
    }
    _channels.clear();
    for (final channel in _unreadChannels.values) {
      await supabase.removeChannel(channel);
    }
    _unreadChannels.clear();
  }
}
