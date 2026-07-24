import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// Milestone 7.2 (Notification Handling).
///
/// Phase 8.5G update: previously this read `AuthCubit`'s in-memory
/// state, which only reflects an explicit login()/register() call made
/// during the current app session — it has no way to see a session
/// Firebase already restored from disk (e.g. app was killed and
/// relaunched while still signed in). It now resolves the uid straight
/// from `FirebaseAuth.instance.currentUser`, matching the rest of the
/// app: FirebaseAuth is the single source of truth for identity, not
/// AuthCubit. `context` is kept in the signature (unused) so callers
/// don't need to change.
///
/// This class still holds the pending chatId for a terminated-launch or
/// pre-login notification tap; once login completes and HomeScreen
/// builds, it is consumed and used to navigate straight to ChatScreen.
class PendingChatNavigation {
  PendingChatNavigation._privateConstructor();
  static final PendingChatNavigation instance = PendingChatNavigation._privateConstructor();

  String? _pendingChatId;

  void setPendingChatId(String chatId) {
    _pendingChatId = chatId;
  }

  /// pending chatId রিটার্ন করে এবং সাথে সাথে ক্লিয়ার করে দেয় — যাতে একবারই
  /// consume হয় (ডুপ্লিকেট নেভিগেশন প্রতিরোধ)।
  String? consumePendingChatId() {
    final id = _pendingChatId;
    _pendingChatId = null;
    return id;
  }

  /// FirebaseAuth.currentUser থেকে সরাসরি uid রিটার্ন করে — authenticated
  /// না থাকলে null। এটাই এখন single source of truth (AuthCubit নয়)।
  String? resolveCurrentUserId(BuildContext context) {
    return FirebaseAuth.instance.currentUser?.uid;
  }
}
