import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/profile/data/datasources/profile_remote_data_source.dart';

class SharedPresenceManager {
  SharedPresenceManager({required this.supabase, required this.remoteDataSource});

  final SupabaseClient supabase;
  final ProfileRemoteDataSource remoteDataSource;

  static const int _kMaxUidsPerChannel = 100;

  static const Duration _kRebuildDebounce = Duration(milliseconds: 300);

  final Map<String, int> _refCounts = {};

  final Map<String, Map<String, dynamic>> _latest = {};

  final Map<String, Set<MultiStreamController<Map<String, dynamic>>>> _listeners = {};

  final Map<int, List<String>> _chunkMembers = {};
  final Map<String, int> _uidToChunk = {};
  final Map<int, RealtimeChannel> _chunkChannels = {};
  int _nextChunkIndex = 0;

  final Set<int> _reconnectInFlight = {};

  Timer? _debounceTimer;
  bool _rebuilding = false;
  bool _rebuildQueued = false;

  Stream<Map<String, dynamic>> watch(String supabaseUid) {
    return Stream.multi((controller) {
      _register(supabaseUid);

      final cached = _latest[supabaseUid];
      if (cached != null) controller.addSync(cached);

      _listeners.putIfAbsent(supabaseUid, () => {}).add(controller);

      controller.onCancel = () {
        _listeners[supabaseUid]?.remove(controller);
        if (_listeners[supabaseUid]?.isEmpty ?? false) {
          _listeners.remove(supabaseUid);
        }
        _unregister(supabaseUid);
      };
    }, isBroadcast: true);
  }

  void _register(String uid) {
    _refCounts[uid] = (_refCounts[uid] ?? 0) + 1;
    _scheduleRebuild();
  }

  void _unregister(String uid) {
    final next = (_refCounts[uid] ?? 0) - 1;
    if (next <= 0) {
      _refCounts.remove(uid);
    } else {
      _refCounts[uid] = next;
    }
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_kRebuildDebounce, () {
      unawaited(_rebuild());
    });
  }

  Future<void> _rebuild() async {
    if (_rebuilding) {
      _rebuildQueued = true;
      return;
    }
    _rebuilding = true;
    try {
      final active = _refCounts.keys.toSet();
      final currentlyAssigned = _uidToChunk.keys.toSet();
      final newUids = active.difference(currentlyAssigned);
      final removedUids = currentlyAssigned.difference(active);

      final affectedChunks = <int>{};

      for (final uid in removedUids) {
        final idx = _uidToChunk.remove(uid);
        if (idx != null) {
          _chunkMembers[idx]?.remove(uid);
          affectedChunks.add(idx);
        }
        _latest.remove(uid);
      }

      if (removedUids.isNotEmpty) {
        _consolidateChunks(affectedChunks);
      }

      if (newUids.isNotEmpty) {
        final coldUids = newUids.where((uid) => !_latest.containsKey(uid)).toList();
        if (coldUids.isNotEmpty) {
          try {
            final rows = await remoteDataSource.fetchPresenceRowsBatch(coldUids);
            for (final row in rows) {
              final uid = row['user_id'] as String?;
              if (uid != null) _emit(uid, row);
            }
          } catch (e, st) {
            debugPrint('SharedPresenceManager: batched presence fetch failed (non-fatal): $e\n$st');
          }
        }

        for (final uid in newUids) {
          int? target;
          for (final entry in _chunkMembers.entries) {
            if (entry.value.length < _kMaxUidsPerChannel) {
              target = entry.key;
              break;
            }
          }
          target ??= _nextChunkIndex++;
          _chunkMembers.putIfAbsent(target, () => <String>[]).add(uid);
          _uidToChunk[uid] = target;
          affectedChunks.add(target);
        }
      }

      for (final idx in _priorityOrder(affectedChunks)) {
        await _resubscribeChunk(idx);
      }
    } finally {
      _rebuilding = false;
      if (_rebuildQueued) {
        _rebuildQueued = false;
        await _rebuild();
      }
    }
  }

  void _consolidateChunks(Set<int> affectedChunks) {
    if (_chunkMembers.length < 2) return;
    final order = _chunkMembers.keys.toList()
      ..sort((a, b) => (_chunkMembers[a]?.length ?? 0).compareTo(_chunkMembers[b]?.length ?? 0));

    for (var i = 0; i < order.length; i++) {
      final srcIdx = order[i];
      final src = _chunkMembers[srcIdx];
      if (src == null || src.isEmpty) continue;
      for (var j = i + 1; j < order.length; j++) {
        final dstIdx = order[j];
        final dst = _chunkMembers[dstIdx];
        if (dst == null) continue;
        if (dst.length + src.length > _kMaxUidsPerChannel) continue;

        dst.addAll(src);
        for (final uid in src) {
          _uidToChunk[uid] = dstIdx;
        }
        _chunkMembers.remove(srcIdx);
        affectedChunks
          ..add(dstIdx)
          ..add(srcIdx);
        break;
      }
    }
  }

  List<int> _priorityOrder(Set<int> affectedChunks) {
    int score(int idx) {
      final members = _chunkMembers[idx];
      if (members == null || members.isEmpty) return -1;
      var live = 0;
      for (final uid in members) {
        final listeners = _listeners[uid];
        if (listeners != null && listeners.isNotEmpty) live++;
      }
      return live;
    }

    final ordered = affectedChunks.toList()..sort((a, b) => score(b).compareTo(score(a)));
    return ordered;
  }

  Future<void> _resubscribeChunk(int idx) async {
    final oldChannel = _chunkChannels.remove(idx);
    if (oldChannel != null) {
      await supabase.removeChannel(oldChannel);
    }

    final members = _chunkMembers[idx];
    if (members == null || members.isEmpty) {
      _chunkMembers.remove(idx);
      _reconnectInFlight.remove(idx);
      return;
    }

    final memberSnapshot = List<String>.of(members);
    final channel = supabase.channel('shared_presence_chunk_$idx');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'user_presence',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.inFilter,
        column: 'user_id',
        value: memberSnapshot,
      ),
      callback: (payload) {
        final row = payload.newRecord;
        final uid = row['user_id'] as String?;
        if (uid == null || row.isEmpty) return;
        _emit(uid, row);
      },
    );

    bool firstSubscribe = true;
    channel.subscribe((status, error) async {
      if (status != RealtimeSubscribeStatus.subscribed) return;
      if (firstSubscribe) {
        firstSubscribe = false;
        return;
      }
      if (_reconnectInFlight.contains(idx)) return;
      _reconnectInFlight.add(idx);
      final currentMembers = _chunkMembers[idx];
      if (currentMembers == null || currentMembers.isEmpty) {
        _reconnectInFlight.remove(idx);
        return;
      }
      try {
        final rows = await remoteDataSource.fetchPresenceRowsBatch(List<String>.of(currentMembers));
        for (final row in rows) {
          final uid = row['user_id'] as String?;
          if (uid != null) _emit(uid, row);
        }
      } catch (_) {
      } finally {
        _reconnectInFlight.remove(idx);
      }
    });

    _chunkChannels[idx] = channel;
  }

  bool _isFreshEnough(String uid, Map<String, dynamic> incoming) {
    final existing = _latest[uid];
    if (existing == null) return true;
    final incomingRaw = incoming['updated_at'];
    final existingRaw = existing['updated_at'];
    if (incomingRaw is String && existingRaw is String) {
      final incomingTime = DateTime.tryParse(incomingRaw);
      final existingTime = DateTime.tryParse(existingRaw);
      if (incomingTime != null && existingTime != null) {
        return !incomingTime.isBefore(existingTime);
      }
    }
    return true;
  }

  void _emit(String uid, Map<String, dynamic> row) {
    if (!_isFreshEnough(uid, row)) return;
    _latest[uid] = row;
    final listeners = _listeners[uid];
    if (listeners == null || listeners.isEmpty) return;
    for (final controller in List<MultiStreamController<Map<String, dynamic>>>.of(listeners)) {
      controller.addSync(row);
    }
  }

  Future<Map<String, Map<String, dynamic>>> primeWarmCache(Iterable<String> supabaseUids) async {
    final requested = supabaseUids.toSet();
    final coldUids = requested.where((uid) => !_latest.containsKey(uid)).toList();
    if (coldUids.isNotEmpty) {
      try {
        final rows = await remoteDataSource.fetchPresenceRowsBatch(coldUids);
        for (final row in rows) {
          final uid = row['user_id'] as String?;
          if (uid != null) _emit(uid, row);
        }
      } catch (e, st) {
        debugPrint('SharedPresenceManager: primeWarmCache failed (non-fatal): $e\n$st');
      }
    }
    final result = <String, Map<String, dynamic>>{};
    for (final uid in requested) {
      final row = _latest[uid];
      if (row != null) result[uid] = row;
    }
    return result;
  }
}
