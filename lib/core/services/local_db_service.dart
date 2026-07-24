import 'package:hive_flutter/hive_flutter.dart';

/// TASK 2 (WhatsApp-like local message architecture) — on-device message
/// cache, backed by Hive.
///
/// One box per chat (`messages_<chatId>`), keyed by `messageId`, storing the
/// plain `Map<String, dynamic>` from `MessageModel.toCacheJson()` — no
/// custom TypeAdapter / build_runner step required since every value is a
/// Hive-native primitive (String/int/double/bool/List).
///
/// A second, small box (`chat_sync_meta`) tracks the last-synced watermark
/// per chat, so `ChatRepositoryImpl.streamMessages` / `streamGroupMessages`
/// know where to resume the Firestore delta query from (see those files for
/// the read-optimization explanation) instead of re-downloading history.
class LocalDbService {
  LocalDbService._();
  static bool _initialized = false;

  static const String syncMetaBoxName = 'chat_sync_meta';

  /// Call once, before runApp — mirrors FriendProfileCacheService.warmUp().
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _initialized = true;
  }

  static String _messagesBoxName(String chatId) => 'messages_$chatId';

  static Future<Box<Map>> messagesBox(String chatId) async {
    final name = _messagesBoxName(chatId);
    if (Hive.isBoxOpen(name)) return Hive.box<Map>(name);
    return Hive.openBox<Map>(name);
  }

  static Future<Box> syncMetaBox() async {
    if (Hive.isBoxOpen(syncMetaBoxName)) return Hive.box(syncMetaBoxName);
    return Hive.openBox(syncMetaBoxName);
  }
}
