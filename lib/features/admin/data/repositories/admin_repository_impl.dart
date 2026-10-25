import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/offline_queue.dart';
import '../../../../core/supabase/user_id_bridge.dart';
import '../../domain/entities/admin_action_log_entry.dart';
import '../../domain/entities/admin_dashboard_stats.dart';
import '../../domain/entities/admin_user_record.dart';
import '../../domain/entities/ban_record.dart';
import '../../domain/entities/ban_type.dart';
import '../../domain/entities/moderation_report.dart';
import '../../domain/entities/report_status.dart';
import '../../domain/entities/report_type.dart';
import '../../domain/entities/user_warning.dart';
import '../../domain/repositories/admin_repository.dart';
import '../datasources/admin_local_data_source.dart';
import '../datasources/admin_remote_data_source.dart';
import '../models/admin_action_log_model.dart';
import '../models/admin_user_record_model.dart';
import '../models/ban_record_model.dart';
import '../models/moderation_report_model.dart';
import '../models/user_warning_model.dart';

const Duration _kSyncTimeout = Duration(seconds: 15);

class AdminRepositoryImpl implements AdminRepository {
  final AdminRemoteDataSource remoteDataSource;
  final AdminLocalDataSource localDataSource;
  final SupabaseClient supabase;
  final OfflineQueueManager offlineQueue;

  AdminRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.supabase,
    OfflineQueueManager? offlineQueue,
  }) : offlineQueue = offlineQueue ?? OfflineQueueManager.instance;

  bool _realtimeStarted = false;

  void _ensureRealtime() {
    if (_realtimeStarted) return;
    _realtimeStarted = true;
    remoteDataSource.watchUsers((row) async {
      final id = row['id'] as String?;
      if (id == null) return;
      try {
        await localDataSource.upsertUserRow(id, row);
      } catch (_) {}
    });
    remoteDataSource.watchReports((row) async {
      try {
        await localDataSource.upsertReportRow(row);
      } catch (_) {}
    });
  }

  String? _currentSupabaseUid() => supabase.auth.currentUser?.id;

  Future<String> _toSupabaseUid(String firebaseUid) {
    return UserIdBridge.resolve(firebaseUid, currentSupabaseUserId: _currentSupabaseUid());
  }

  Future<String> _toFirebaseUid(String supabaseUid) async {
    return (await UserIdBridge.reverseResolve(supabaseUid)) ?? supabaseUid;
  }

  Failure _mapError(Object e) {
    if (e is CacheException) return FirebaseFailure(e.message);
    if (e is ServerException) return FirebaseFailure(e.message);
    if (e is NetworkException) return NetworkFailure(e.message);
    return FirebaseFailure(e.toString());
  }


  @override
  Future<Either<Failure, AdminDashboardStats>> getDashboardStats() async {
    _ensureRealtime();
    try {
      final totalUsers = await remoteDataSource.countUsers();
      final totalGroups = await remoteDataSource.countChats(isGroup: true);
      final totalChats = await remoteDataSource.countChats(isGroup: false);
      final totalFriends = await remoteDataSource.countAcceptedFriendships();
      final stats = AdminDashboardStats(
        totalUsers: totalUsers,
        totalFriends: totalFriends,
        totalChats: totalChats,
        totalGroups: totalGroups,
      );
      await localDataSource.setCachedDashboardStats(stats);
      return Right(stats);
    } catch (e) {
      try {
        final cached = await localDataSource.getCachedDashboardStats();
        if (cached != null) return Right(cached);
      } catch (_) {}
      return Left(_mapError(e));
    }
  }


  Future<AdminUserRecord> _rowToRecord(String firebaseUid, Map<String, dynamic> row) async {
    return AdminUserRecordModel.fromSupabaseRow(row, firebaseUid: firebaseUid);
  }

  @override
  Future<Either<Failure, AdminUserRecord?>> lookupUserByUid(String uid) async {
    _ensureRealtime();
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return const Right(null);
    try {
      final supabaseUid = await _toSupabaseUid(trimmed);
      final row = await remoteDataSource.fetchUserById(supabaseUid);
      if (row == null) {
        final cached = await localDataSource.getCachedUserRow(supabaseUid);
        if (cached == null) return const Right(null);
        return Right(await _rowToRecord(trimmed, cached));
      }
      await localDataSource.upsertUserRow(supabaseUid, row);
      return Right(await _rowToRecord(trimmed, row));
    } catch (e) {
      try {
        final supabaseUid = await _toSupabaseUid(trimmed);
        final cached = await localDataSource.getCachedUserRow(supabaseUid);
        if (cached != null) return Right(await _rowToRecord(trimmed, cached));
      } catch (_) {}
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, List<AdminUserRecord>>> lookupUsersByUsername(String query) async {
    _ensureRealtime();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const Right(<AdminUserRecord>[]);
    try {
      final rows = await remoteDataSource.searchUsersByUsername(trimmed);
      final records = <AdminUserRecord>[];
      for (final row in rows) {
        final supabaseUid = row['id'] as String?;
        if (supabaseUid == null) continue;
        await localDataSource.upsertUserRow(supabaseUid, row);
        final firebaseUid = await _toFirebaseUid(supabaseUid);
        records.add(await _rowToRecord(firebaseUid, row));
      }
      return Right(records);
    } catch (e) {
      try {
        final cached = await localDataSource.searchCachedUsersByUsername(trimmed);
        if (cached.isNotEmpty) {
          final records = <AdminUserRecord>[];
          for (final row in cached) {
            final supabaseUid = row['id'] as String? ?? '';
            final firebaseUid = await _toFirebaseUid(supabaseUid);
            records.add(await _rowToRecord(firebaseUid, row));
          }
          return Right(records);
        }
      } catch (_) {}
      return Left(_mapError(e));
    }
  }


  Future<void> _logAction({
    required String action,
    required String actorSupabaseId,
    String? targetSupabaseId,
    String? reportId,
    String? details,
  }) {
    return remoteDataSource.insertActionLog({
      'action': action,
      'actor_id': actorSupabaseId,
      'target_id': targetSupabaseId,
      'report_id': reportId,
      'details': details,
    });
  }

  @override
  Future<Either<Failure, void>> banUser({
    required String targetUid,
    required String reason,
    required String issuedBy,
    required BanType type,
    DateTime? expiresAt,
  }) async {
    try {
      final supabaseTarget = await _toSupabaseUid(targetUid);
      final supabaseIssuer = await _toSupabaseUid(issuedBy);
      final expiresAtIso = expiresAt?.toUtc().toIso8601String();
      await offlineQueue.addToQueue(() async {
        await remoteDataSource.insertBanHistory({
          'target_id': supabaseTarget,
          'reason': reason,
          'issued_by': supabaseIssuer,
          'status': 'active',
          'type': banTypeToString(type),
          'expires_at': expiresAtIso,
        });
        await remoteDataSource.updateUserModerationFields(supabaseTarget, {
          'is_banned': true,
          'banned_at': DateTime.now().toUtc().toIso8601String(),
          'ban_type': banTypeToString(type),
          'ban_expires_at': expiresAtIso,
        });
        await _logAction(
          action: 'ban',
          actorSupabaseId: supabaseIssuer,
          targetSupabaseId: supabaseTarget,
          details: reason,
        );
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> unbanUser({required String targetUid, required String issuedBy}) async {
    try {
      final supabaseTarget = await _toSupabaseUid(targetUid);
      final supabaseIssuer = await _toSupabaseUid(issuedBy);
      await offlineQueue.addToQueue(() async {
        await remoteDataSource.liftActiveBans(supabaseTarget);
        await remoteDataSource.updateUserModerationFields(supabaseTarget, {
          'is_banned': false,
          'banned_at': null,
          'ban_type': null,
          'ban_expires_at': null,
        });
        await _logAction(action: 'unban', actorSupabaseId: supabaseIssuer, targetSupabaseId: supabaseTarget);
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> disableAccount({required String targetUid, required String issuedBy}) async {
    try {
      final supabaseTarget = await _toSupabaseUid(targetUid);
      final supabaseIssuer = await _toSupabaseUid(issuedBy);
      await offlineQueue.addToQueue(() async {
        await remoteDataSource.updateUserModerationFields(supabaseTarget, {
          'is_disabled': true,
          'disabled_at': DateTime.now().toUtc().toIso8601String(),
        });
        await _logAction(action: 'disable', actorSupabaseId: supabaseIssuer, targetSupabaseId: supabaseTarget);
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> restoreAccount({required String targetUid, required String issuedBy}) async {
    try {
      final supabaseTarget = await _toSupabaseUid(targetUid);
      final supabaseIssuer = await _toSupabaseUid(issuedBy);
      await offlineQueue.addToQueue(() async {
        await remoteDataSource.updateUserModerationFields(supabaseTarget, {
          'is_disabled': false,
          'disabled_at': null,
        });
        await _logAction(action: 'restore', actorSupabaseId: supabaseIssuer, targetSupabaseId: supabaseTarget);
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  Future<BanRecord> _rowToBanRecord(Map<String, dynamic> row) async {
    final targetUid = await _toFirebaseUid(row['target_id'] as String? ?? '');
    final issuedBy = await _toFirebaseUid(row['issued_by'] as String? ?? '');
    return BanRecordModel.fromSupabaseRow(row, targetUid: targetUid, issuedBy: issuedBy);
  }

  @override
  Future<Either<Failure, List<BanRecord>>> getBanHistory(String targetUid) async {
    try {
      final supabaseTarget = await _toSupabaseUid(targetUid);
      final rows = await remoteDataSource.fetchBanHistory(supabaseTarget);
      await localDataSource.setCachedBanHistory(supabaseTarget, rows);
      final records = await Future.wait(rows.map(_rowToBanRecord));
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(records);
    } catch (e) {
      try {
        final supabaseTarget = await _toSupabaseUid(targetUid);
        final cached = await localDataSource.getCachedBanHistory(supabaseTarget);
        if (cached.isNotEmpty) {
          final records = await Future.wait(cached.map(_rowToBanRecord));
          records.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return Right(records);
        }
      } catch (_) {}
      return Left(_mapError(e));
    }
  }


  Future<Either<Failure, void>> _submitReport({
    required ReportType type,
    required String reporterUid,
    required String reason,
    String? targetUid,
    String? messageId,
    String? chatId,
    String? groupId,
    String? description,
  }) async {
    try {
      final supabaseReporter = await _toSupabaseUid(reporterUid);
      final String targetId;
      switch (type) {
        case ReportType.user:
          targetId = await _toSupabaseUid(targetUid!);
          break;
        case ReportType.message:
          targetId = messageId!;
          break;
        case ReportType.group:
          targetId = groupId!;
          break;
      }
      final extra = ModerationReportModel.encodeDetails(description: description, chatId: chatId);
      final detailsJson = extra.isEmpty ? null : jsonEncode(extra);

      await offlineQueue.addToQueue(() async {
        await remoteDataSource.insertReport({
          'reporter_id': supabaseReporter,
          'target_type': reportTypeToString(type),
          'target_id': targetId,
          'reason': reason,
          'details': detailsJson,
          'status': 'open',
        });
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> reportUser({
    required String reporterUid,
    required String targetUid,
    required String reason,
    String? description,
  }) {
    return _submitReport(
      type: ReportType.user,
      reporterUid: reporterUid,
      reason: reason,
      targetUid: targetUid,
      description: description,
    );
  }

  @override
  Future<Either<Failure, void>> reportMessage({
    required String reporterUid,
    required String messageId,
    required String chatId,
    required String reason,
  }) {
    return _submitReport(
      type: ReportType.message,
      reporterUid: reporterUid,
      reason: reason,
      messageId: messageId,
      chatId: chatId,
    );
  }

  @override
  Future<Either<Failure, void>> reportGroup({
    required String reporterUid,
    required String groupId,
    required String reason,
  }) {
    return _submitReport(type: ReportType.group, reporterUid: reporterUid, reason: reason, groupId: groupId);
  }

  Future<ModerationReport> _rowToReport(Map<String, dynamic> row) async {
    final reporterUid = await _toFirebaseUid(row['reporter_id'] as String? ?? '');
    final type = reportTypeFromString(row['target_type'] as String?);
    String? targetUid;
    if (type == ReportType.user) {
      final targetId = row['target_id'] as String?;
      if (targetId != null) targetUid = await _toFirebaseUid(targetId);
    }
    return ModerationReportModel.fromSupabaseRow(row, reporterUid: reporterUid, targetUid: targetUid);
  }

  Future<void> _syncReports() async {
    try {
      final since = await localDataSource.getReportsLastSyncedAt();
      final rows = since == null
          ? await remoteDataSource.fetchAllReports()
          : await remoteDataSource.fetchReportsUpdatedSince(since);
      if (rows.isEmpty) {
        if (since == null) await localDataSource.setReportsLastSyncedAt(DateTime.now());
        return;
      }
      await localDataSource.upsertReports(rows);
      DateTime latest = since ?? DateTime.fromMillisecondsSinceEpoch(0);
      for (final row in rows) {
        final ts = row['updated_at'];
        if (ts is String) {
          final parsed = DateTime.parse(ts).toLocal();
          if (parsed.isAfter(latest)) latest = parsed;
        }
      }
      await localDataSource.setReportsLastSyncedAt(latest);
    } catch (_) {
    }
  }

  @override
  Future<Either<Failure, List<ModerationReport>>> getModerationReports() async {
    _ensureRealtime();
    await _syncReports().timeout(_kSyncTimeout, onTimeout: () {});
    try {
      final cached = await localDataSource.getCachedReports();
      final reports = await Future.wait(cached.map(_rowToReport));
      reports.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(reports);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> updateReportStatus({
    required String reportId,
    required ReportStatus status,
    required String adminUid,
  }) async {
    try {
      final supabaseAdmin = await _toSupabaseUid(adminUid);
      final column = reportStatusToColumn(status);
      await offlineQueue.addToQueue(() async {
        await remoteDataSource.updateReportStatus(reportId, column);
        await _logAction(
          action: status == ReportStatus.resolved ? 'report_resolved' : 'report_reviewed',
          actorSupabaseId: supabaseAdmin,
          reportId: reportId,
        );
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }


  @override
  Future<Either<Failure, void>> issueWarning({
    required String userUid,
    required String reason,
    required String issuedBy,
  }) async {
    try {
      final supabaseUser = await _toSupabaseUid(userUid);
      final supabaseIssuer = await _toSupabaseUid(issuedBy);
      await offlineQueue.addToQueue(() async {
        await remoteDataSource.insertWarning({
          'user_id': supabaseUser,
          'reason': reason,
          'issued_by': supabaseIssuer,
        });
        await _logAction(
          action: 'warning_issued',
          actorSupabaseId: supabaseIssuer,
          targetSupabaseId: supabaseUser,
          details: reason,
        );
      });
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  Future<UserWarning> _rowToWarning(Map<String, dynamic> row, String userUid) async {
    final issuedBy = await _toFirebaseUid(row['issued_by'] as String? ?? '');
    return UserWarningModel.fromSupabaseRow(row, userUid: userUid, issuedBy: issuedBy);
  }

  @override
  Future<Either<Failure, List<UserWarning>>> getUserWarnings(String userUid) async {
    try {
      final supabaseUser = await _toSupabaseUid(userUid);
      final rows = await remoteDataSource.fetchWarnings(supabaseUser);
      await localDataSource.setCachedWarnings(supabaseUser, rows);
      final list = await Future.wait(rows.map((r) => _rowToWarning(r, userUid)));
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(list);
    } catch (e) {
      try {
        final supabaseUser = await _toSupabaseUid(userUid);
        final cached = await localDataSource.getCachedWarnings(supabaseUser);
        if (cached.isNotEmpty) {
          final list = await Future.wait(cached.map((r) => _rowToWarning(r, userUid)));
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return Right(list);
        }
      } catch (_) {}
      return Left(_mapError(e));
    }
  }


  Future<AdminActionLogEntry> _rowToLogEntry(Map<String, dynamic> row) async {
    final actorUid = await _toFirebaseUid(row['actor_id'] as String? ?? '');
    final targetIdRaw = row['target_id'] as String?;
    final targetUid = targetIdRaw != null ? await _toFirebaseUid(targetIdRaw) : null;
    return AdminActionLogModel.fromSupabaseRow(row, actorUid: actorUid, targetUid: targetUid);
  }

  Future<void> _syncActionLog() async {
    try {
      final since = await localDataSource.getActionLogLastSyncedAt();
      final rows = since == null
          ? await remoteDataSource.fetchAllActionLog()
          : await remoteDataSource.fetchActionLogCreatedSince(since);
      if (rows.isEmpty) {
        if (since == null) await localDataSource.setActionLogLastSyncedAt(DateTime.now());
        return;
      }
      final existing = await localDataSource.getCachedActionLog();
      final byId = {for (final r in existing) r['id'] as String? ?? '': r};
      for (final r in rows) {
        final id = r['id'] as String?;
        if (id != null) byId[id] = r;
      }
      await localDataSource.setCachedActionLog(byId.values.toList());
      DateTime latest = since ?? DateTime.fromMillisecondsSinceEpoch(0);
      for (final row in rows) {
        final ts = row['created_at'];
        if (ts is String) {
          final parsed = DateTime.parse(ts).toLocal();
          if (parsed.isAfter(latest)) latest = parsed;
        }
      }
      await localDataSource.setActionLogLastSyncedAt(latest);
    } catch (_) {
    }
  }

  @override
  Future<Either<Failure, List<AdminActionLogEntry>>> getActionLog() async {
    await _syncActionLog().timeout(_kSyncTimeout, onTimeout: () {});
    try {
      final cached = await localDataSource.getCachedActionLog();
      final entries = await Future.wait(cached.map(_rowToLogEntry));
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(entries);
    } catch (e) {
      return Left(_mapError(e));
    }
  }


  @override
  Stream<void> watchAdminActivity() => remoteDataSource.watchAdminActivity();
}
