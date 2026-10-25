import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../domain/entities/notification_item_entity.dart';
import '../../domain/usecases/delete_notification_usecase.dart';
import '../../domain/usecases/mark_all_notifications_read_usecase.dart';
import '../../domain/usecases/mark_notification_read_usecase.dart';
import '../../domain/usecases/stream_notifications_usecase.dart';

const _kLoadTimeout = Duration(seconds: 15);

abstract class NotificationEvent {}

class LoadNotificationsEvent extends NotificationEvent {
  final String uid;
  LoadNotificationsEvent(this.uid);
}

class RefreshNotificationsEvent extends NotificationEvent {
  final String uid;
  RefreshNotificationsEvent(this.uid);
}

class MarkNotificationReadEvent extends NotificationEvent {
  final String uid;
  final String notificationId;
  MarkNotificationReadEvent({required this.uid, required this.notificationId});
}

class MarkAllNotificationsReadEvent extends NotificationEvent {
  final String uid;
  MarkAllNotificationsReadEvent(this.uid);
}

class DeleteNotificationEvent extends NotificationEvent {
  final String uid;
  final String notificationId;
  DeleteNotificationEvent({required this.uid, required this.notificationId});
}

abstract class NotificationState {}

class NotificationInitial extends NotificationState {}

class NotificationLoading extends NotificationState {}

class NotificationLoadedState extends NotificationState {
  final List<NotificationItemEntity> notifications;
  NotificationLoadedState(this.notifications);

  int get unreadCount => notifications.where((n) => !n.isRead).length;
}

class NotificationErrorState extends NotificationState {
  final String message;
  NotificationErrorState({required this.message});
}

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final StreamNotificationsUseCase streamNotificationsUseCase;
  final MarkNotificationReadUseCase markNotificationReadUseCase;
  final MarkAllNotificationsReadUseCase markAllNotificationsReadUseCase;
  final DeleteNotificationUseCase deleteNotificationUseCase;

  Timer? _loadTimeoutTimer;
  List<NotificationItemEntity> _latest = [];

  NotificationBloc({
    required this.streamNotificationsUseCase,
    required this.markNotificationReadUseCase,
    required this.markAllNotificationsReadUseCase,
    required this.deleteNotificationUseCase,
  }) : super(NotificationInitial()) {
    on<LoadNotificationsEvent>(_onLoad);
    on<RefreshNotificationsEvent>(_onRefresh);
    on<MarkNotificationReadEvent>(_onMarkRead);
    on<MarkAllNotificationsReadEvent>(_onMarkAllRead);
    on<DeleteNotificationEvent>(_onDelete);
  }

  Future<void> _onLoad(LoadNotificationsEvent event, Emitter<NotificationState> emit) async {
    emit(NotificationLoading());

    bool firstSnapshotReceived = false;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(_kLoadTimeout, () {
      if (!firstSnapshotReceived && !emit.isDone) {
        emit(NotificationErrorState(message: 'Taking too long to load. Please try again.'));
      }
    });

    await emit.forEach<List<NotificationItemEntity>>(
      streamNotificationsUseCase(event.uid),
      onData: (notifications) {
        firstSnapshotReceived = true;
        _loadTimeoutTimer?.cancel();
        _latest = notifications;
        return NotificationLoadedState(notifications);
      },
      onError: (error, stackTrace) {
        firstSnapshotReceived = true;
        _loadTimeoutTimer?.cancel();
        return NotificationErrorState(message: friendlyErrorMessage(error));
      },
    );
    _loadTimeoutTimer?.cancel();
  }

  Future<void> _onRefresh(RefreshNotificationsEvent event, Emitter<NotificationState> emit) async {
    if (state is! NotificationLoadedState && state is! NotificationErrorState) return;
    if (state is NotificationErrorState) {
      await _onLoad(LoadNotificationsEvent(event.uid), emit);
    }
  }

  Future<void> _onMarkRead(MarkNotificationReadEvent event, Emitter<NotificationState> emit) async {
    _applyOptimistic(emit, (n) => n.id == event.notificationId ? n.copyWith(isRead: true) : n);
    try {
      await markNotificationReadUseCase(uid: event.uid, notificationId: event.notificationId);
    } catch (error) {
      emit(NotificationErrorState(message: friendlyErrorMessage(error)));
      emit(NotificationLoadedState(_latest));
    }
  }

  Future<void> _onMarkAllRead(MarkAllNotificationsReadEvent event, Emitter<NotificationState> emit) async {
    _applyOptimistic(emit, (n) => n.copyWith(isRead: true));
    try {
      await markAllNotificationsReadUseCase(event.uid);
    } catch (error) {
      emit(NotificationErrorState(message: friendlyErrorMessage(error)));
      emit(NotificationLoadedState(_latest));
    }
  }

  Future<void> _onDelete(DeleteNotificationEvent event, Emitter<NotificationState> emit) async {
    final previous = _latest;
    _latest = _latest.where((n) => n.id != event.notificationId).toList();
    emit(NotificationLoadedState(_latest));
    try {
      await deleteNotificationUseCase(uid: event.uid, notificationId: event.notificationId);
    } catch (error) {
      _latest = previous;
      emit(NotificationErrorState(message: friendlyErrorMessage(error)));
      emit(NotificationLoadedState(_latest));
    }
  }

  void _applyOptimistic(
    Emitter<NotificationState> emit,
    NotificationItemEntity Function(NotificationItemEntity) transform,
  ) {
    _latest = _latest.map(transform).toList();
    emit(NotificationLoadedState(_latest));
  }

  @override
  Future<void> close() {
    _loadTimeoutTimer?.cancel();
    return super.close();
  }
}
