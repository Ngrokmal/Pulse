import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/widgets.dart';

class PendingChatNavigation {
  PendingChatNavigation._privateConstructor();
  static final PendingChatNavigation instance = PendingChatNavigation._privateConstructor();

  String? _pendingChatId;

  void setPendingChatId(String chatId) {
    _pendingChatId = chatId;
  }

  String? consumePendingChatId() {
    final id = _pendingChatId;
    _pendingChatId = null;
    return id;
  }

  String? resolveCurrentUserId(BuildContext context) {
    return Supabase.instance.client.auth.currentUser?.id;
  }
}
