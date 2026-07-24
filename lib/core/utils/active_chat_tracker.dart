class ActiveChatTracker {
  ActiveChatTracker._privateConstructor();
  static final ActiveChatTracker instance = ActiveChatTracker._privateConstructor();

  String? _currentActiveChatId;

  void setActiveChat(String chatId) {
    _currentActiveChatId = chatId;
  }

  void clearActiveChat() {
    _currentActiveChatId = null;
  }

  bool isChatActive(String chatId) {
    return _currentActiveChatId == chatId;
  }
}
