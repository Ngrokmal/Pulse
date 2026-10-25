import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  DeviceIdService._();
  static final DeviceIdService instance = DeviceIdService._();

  static const String _boxName = 'device_identity';
  static const String _key = 'device_id';

  String? _cached;

  String? get cachedDeviceId => _cached;

  Future<String> getOrCreateDeviceId() async {
    final cached = _cached;
    if (cached != null) return cached;

    final box = Hive.isBoxOpen(_boxName) ? Hive.box<String>(_boxName) : await Hive.openBox<String>(_boxName);
    var id = box.get(_key);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await box.put(_key, id);
    }
    _cached = id;
    return id;
  }
}
