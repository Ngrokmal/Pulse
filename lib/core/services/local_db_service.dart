import 'package:hive_flutter/hive_flutter.dart';

class LocalDbService {
  LocalDbService._();
  static bool _initialized = false;

  static const String syncMetaBoxName = 'chat_sync_meta';

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

  static Future<Box<Map>> homeChatListBox(String boxName) async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<Map>(boxName);
    return Hive.openBox<Map>(boxName);
  }

  static Future<Box<String>> friendsBox(String uid) async {
    final name = 'friends_$uid';
    if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
    return Hive.openBox<String>(name);
  }

  static Future<Box<Map>> notificationsBox(String uid) async {
    final name = 'notifications_$uid';
    if (Hive.isBoxOpen(name)) return Hive.box<Map>(name);
    return Hive.openBox<Map>(name);
  }

  static Future<Box<Map>> alertSoundsBox(String ownerUid) async {
    final name = 'alert_sounds_$ownerUid';
    if (Hive.isBoxOpen(name)) return Hive.box<Map>(name);
    return Hive.openBox<Map>(name);
  }

  static const String groupInfoBoxName = 'group_info_cache';

  static Future<Box<Map>> groupInfoBox() async {
    if (Hive.isBoxOpen(groupInfoBoxName)) return Hive.box<Map>(groupInfoBoxName);
    return Hive.openBox<Map>(groupInfoBoxName);
  }

  static Future<Box<Map>> groupMembersBox(String groupId) async {
    final name = 'group_members_$groupId';
    if (Hive.isBoxOpen(name)) return Hive.box<Map>(name);
    return Hive.openBox<Map>(name);
  }
}
