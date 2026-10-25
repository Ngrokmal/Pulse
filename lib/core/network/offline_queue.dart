import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hive_flutter/hive_flutter.dart';

class _QueuedTask {
  final Future<void> Function() run;
  final Completer<void> completer;
  final String? id;
  final int priority;
  _QueuedTask(this.run, this.completer, {this.id, this.priority = 0});
}

class OfflineQueueManager {
  OfflineQueueManager._privateConstructor();
  static final OfflineQueueManager instance = OfflineQueueManager._privateConstructor();

  final List<_QueuedTask> _queue = [];
  bool _isProcessing = false;

  static const String _persistentBoxName = 'offline_queue_v1';
  final Map<String, Future<void> Function(Map<String, dynamic>)> _handlers = {};
  final Set<String> _activeIds = {};

  int _deletesSinceCompact = 0;
  static const int _compactEvery = 10;

  static const Duration _interTaskDelay = Duration(milliseconds: 300);
  static const int _hydrateBatchSize = 3;
  static const Duration _hydrateBatchDelay = Duration(milliseconds: 400);

  Future<Box> _persistentBox() async {
    if (Hive.isBoxOpen(_persistentBoxName)) return Hive.box(_persistentBoxName);
    return Hive.openBox(_persistentBoxName);
  }

  void registerHandler(String opType, Future<void> Function(Map<String, dynamic> payload) handler) {
    _handlers[opType] = handler;
  }

  Future<void> addPersistentTask({
    required String opType,
    required Map<String, dynamic> payload,
    String? taskId,
    int priority = 0,
  }) async {
    final id = taskId ?? '${opType}_${DateTime.now().microsecondsSinceEpoch}';

    final box = await _persistentBox();
    final existingRaw = box.get(id);
    final preservedEnqueuedAt = existingRaw != null
        ? (Map<String, dynamic>.from(existingRaw as Map)['enqueuedAt'] as num?)?.toInt()
        : null;

    await box.put(id, {
      'opType': opType,
      'payload': payload,
      'priority': priority,
      'enqueuedAt': preservedEnqueuedAt ?? DateTime.now().millisecondsSinceEpoch,
    });

    _activeIds.add(id);
    final future = addToQueue(() => _runPersistent(id, opType), taskId: id, priority: priority);
    unawaited(future.whenComplete(() => _activeIds.remove(id)));
    return future;
  }

  Future<void> _runPersistent(String id, String opType) async {
    final handler = _handlers[opType];
    if (handler == null) {
      throw StateError('OfflineQueueManager: no handler registered for "$opType"');
    }
    final box = await _persistentBox();
    final raw = box.get(id);
    if (raw == null) {
      return;
    }
    final entry = Map<String, dynamic>.from(raw as Map);
    final payload = Map<String, dynamic>.from(entry['payload'] as Map);
    await handler(payload);
    await _deletePersisted(id);
  }

  Future<void> _deletePersisted(String id) async {
    final box = await _persistentBox();
    await box.delete(id);
    _deletesSinceCompact++;
    if (_deletesSinceCompact >= _compactEvery) {
      _deletesSinceCompact = 0;
      try {
        await box.compact();
      } catch (e) {
        debugPrint('OfflineQueueManager: box.compact() failed — $e');
      }
    }
  }

  Future<void> _markFailedBackoff(String id) async {
    final box = await _persistentBox();
    final raw = box.get(id);
    if (raw == null) return;
    final entry = Map<String, dynamic>.from(raw as Map);
    entry['status'] = 'backoff';
    entry['nextAttemptAt'] = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
    await box.put(id, entry);
  }

  Future<void> hydrate() async {
    final box = await _persistentBox();
    final pending = <MapEntry<String, Map<String, dynamic>>>[];
    for (final key in List<dynamic>.from(box.keys)) {
      final id = key as String;
      if (_activeIds.contains(id)) continue;
      final raw = box.get(id);
      if (raw == null) continue;
      final entryMap = Map<String, dynamic>.from(raw as Map);

      final nextAttemptAt = (entryMap['nextAttemptAt'] as num?)?.toInt();
      if (nextAttemptAt != null && DateTime.now().millisecondsSinceEpoch < nextAttemptAt) {
        continue;
      }

      pending.add(MapEntry(id, entryMap));
    }

    pending.sort((a, b) {
      final pa = (a.value['priority'] as num?)?.toInt() ?? 0;
      final pb = (b.value['priority'] as num?)?.toInt() ?? 0;
      if (pa != pb) return pb.compareTo(pa);
      final ta = (a.value['enqueuedAt'] as num?)?.toInt() ?? 0;
      final tb = (b.value['enqueuedAt'] as num?)?.toInt() ?? 0;
      return ta.compareTo(tb);
    });

    for (int i = 0; i < pending.length; i++) {
      if (i > 0 && i % _hydrateBatchSize == 0) {
        await Future.delayed(_hydrateBatchDelay);
      }
      final entry = pending[i];
      final id = entry.key;
      final opType = entry.value['opType'] as String;
      final priority = (entry.value['priority'] as num?)?.toInt() ?? 0;
      _activeIds.add(id);
      final future = addToQueue(() => _runPersistent(id, opType), taskId: id, priority: priority);
      unawaited(future.whenComplete(() => _activeIds.remove(id)));
    }
  }

  void clear() {
    _activeIds.clear();
    if (_queue.isEmpty) return;
    final pending = List<_QueuedTask>.from(_queue);
    _queue.clear();
    for (final task in pending) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(
          StateError('OfflineQueueManager: task cancelled (user signed out)'),
        );
      }
    }
  }

  Future<void> addToQueue(Future<void> Function() task, {String? taskId, int priority = 0}) {
    if (taskId != null) {
      for (final queued in _queue) {
        if (queued.id == taskId) {
          return queued.completer.future;
        }
      }
    }
    final completer = Completer<void>();
    _queue.add(_QueuedTask(task, completer, id: taskId, priority: priority));
    _processQueue();
    return completer.future;
  }

  _QueuedTask _selectNext() {
    var best = _queue.first;
    for (final t in _queue) {
      if (t.priority > best.priority) best = t;
    }
    return best;
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final queuedTask = _selectNext();
      int retryCount = 0;
      bool success = false;
      Object? lastError;

      while (!success && retryCount < 5) {
        try {
          await queuedTask.run();
          success = true;
        } on SocketException catch (e) {
          lastError = e;
          retryCount++;
          final int backoffSeconds = pow(2, retryCount).toInt() + Random().nextInt(2);
          await Future.delayed(Duration(seconds: backoffSeconds));
        } catch (e) {
          lastError = e;
          break;
        }
      }

      if (success) {
        _queue.remove(queuedTask);
        queuedTask.completer.complete();
        if (_queue.isNotEmpty) await Future.delayed(_interTaskDelay);
      } else if (retryCount >= 5) {
        if (queuedTask.id != null) {
          await _markFailedBackoff(queuedTask.id!);
        }
        break;
      } else {
        _queue.remove(queuedTask);
        if (queuedTask.id != null) {
          await _deletePersisted(queuedTask.id!);
        }
        queuedTask.completer.completeError(
          lastError ?? StateError('OfflineQueueManager: task failed'),
        );
      }
    }
    _isProcessing = false;
  }
}
