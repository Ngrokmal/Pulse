import 'dart:async';

class LocalChatCreatedEvent {
  final String uid;
  final Map<String, dynamic>? chatStub;
  const LocalChatCreatedEvent({required this.uid, this.chatStub});
}

class LocalChatCreatedBus {
  LocalChatCreatedBus._();
  static final LocalChatCreatedBus instance = LocalChatCreatedBus._();

  final StreamController<LocalChatCreatedEvent> _controller = StreamController<LocalChatCreatedEvent>.broadcast();

  Stream<LocalChatCreatedEvent> get stream => _controller.stream;

  void emit({required String uid, Map<String, dynamic>? chatStub}) {
    if (!_controller.isClosed) {
      _controller.add(LocalChatCreatedEvent(uid: uid, chatStub: chatStub));
    }
  }
}
