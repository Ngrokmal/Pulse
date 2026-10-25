import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/usecases/stream_unread_notification_count_usecase.dart';

class NotificationBadgeCubit extends Cubit<int> {
  final StreamUnreadNotificationCountUseCase streamUnreadNotificationCountUseCase;
  StreamSubscription<int>? _subscription;

  NotificationBadgeCubit({required this.streamUnreadNotificationCountUseCase}) : super(0);

  void start(String uid) {
    _subscription?.cancel();
    _subscription = streamUnreadNotificationCountUseCase(uid).listen(
      (count) {
        if (!isClosed) emit(count);
      },
      onError: (_) {
      },
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
