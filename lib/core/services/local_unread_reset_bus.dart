import 'dart:async';

class LocalUnreadResetEvent {
  final String uid;
  final String chatId;
  const LocalUnreadResetEvent({required this.uid, required this.chatId});
}

class LocalUnreadResetBus {
  LocalUnreadResetBus._();
  static final LocalUnreadResetBus instance = LocalUnreadResetBus._();

  final StreamController<LocalUnreadResetEvent> _controller = StreamController<LocalUnreadResetEvent>.broadcast();

  Stream<LocalUnreadResetEvent> get stream => _controller.stream;

  void emit({required String uid, required String chatId}) {
    if (!_controller.isClosed) {
      _controller.add(LocalUnreadResetEvent(uid: uid, chatId: chatId));
    }
  }
}
