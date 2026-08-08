import 'dart:async';

class GroupDeltaSyncCoordinator {
  GroupDeltaSyncCoordinator._();
  static final GroupDeltaSyncCoordinator instance = GroupDeltaSyncCoordinator._();

  static const Duration _coalesceWindow = Duration(milliseconds: 150);

  Future<void> Function(List<String> groupIds)? _runBatchedDelta;

  final Set<String> _activeGroupIds = {};
  final Map<String, void Function()> _onSyncedListeners = {};

  Timer? _pendingTimer;
  bool _syncInFlight = false;
  bool _rerunRequested = false;

  void configure(Future<void> Function(List<String> groupIds) runBatchedDelta) {
    _runBatchedDelta = runBatchedDelta;
  }

  void registerActiveGroup(String groupId, void Function() onSynced) {
    _activeGroupIds.add(groupId);
    _onSyncedListeners[groupId] = onSynced;
  }

  void unregisterActiveGroup(String groupId) {
    _activeGroupIds.remove(groupId);
    _onSyncedListeners.remove(groupId);
  }

  void notifyReconnect() => _scheduleSync();

  void notifyAppResumed() => _scheduleSync();

  void _scheduleSync() {
    if (_activeGroupIds.isEmpty || _runBatchedDelta == null) return;
    if (_syncInFlight) {
      _rerunRequested = true;
      return;
    }
    _pendingTimer ??= Timer(_coalesceWindow, _runSync);
  }

  Future<void> _runSync() async {
    _pendingTimer = null;
    final runner = _runBatchedDelta;
    if (runner == null || _activeGroupIds.isEmpty) return;

    _syncInFlight = true;
    try {
      final groupIds = _activeGroupIds.toList(growable: false);
      await runner(groupIds);
      for (final listener in _onSyncedListeners.values.toList(growable: false)) {
        listener();
      }
    } finally {
      _syncInFlight = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        _scheduleSync();
      }
    }
  }
}
