import 'dart:async';
import 'package:flutter/foundation.dart';
import '../constants/presence_constants.dart';
import '../supabase/supabase_init.dart';
import 'device_id_service.dart';
import '../../features/profile/domain/usecases/heartbeat_presence_usecase.dart';

class PresenceActivityPinger {
  PresenceActivityPinger(this._heartbeatPresenceUseCase);

  final HeartbeatPresenceUseCase _heartbeatPresenceUseCase;

  static const Duration _kThrottle = PresenceConstants.heartbeatInterval;

  DateTime? _lastPingAt;

  void ping() {
    final uid = SupabaseInit.client.auth.currentUser?.id;
    if (uid == null) return;
    final deviceId = DeviceIdService.instance.cachedDeviceId;
    if (deviceId == null) return;

    final now = DateTime.now();
    if (_lastPingAt != null && now.difference(_lastPingAt!) < _kThrottle) {
      return;
    }
    _lastPingAt = now;
    unawaited(_heartbeatPresenceUseCase(uid: uid, deviceId: deviceId));
  }

  @visibleForTesting
  void resetThrottleForTest() => _lastPingAt = null;
}
