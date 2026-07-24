import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../../domain/entities/admin_action_log_entry.dart';
import '../../domain/entities/admin_dashboard_stats.dart';
import '../../domain/entities/admin_user_record.dart';
import '../../domain/entities/ban_record.dart';
import '../../domain/entities/ban_status.dart';
import '../../domain/entities/ban_type.dart';
import '../../domain/entities/moderation_report.dart';
import '../../domain/entities/report_status.dart';
import '../../domain/entities/report_type.dart';
import '../../domain/entities/user_warning.dart';
import '../../domain/repositories/admin_repository.dart';

/// Phase 8.6A (Admin Foundation)
///
/// Reads existing collections only ('users', 'chats', and the 'friends'
/// subcollection group already used by the friend/profile modules) — no
/// new collections, no Cloud Functions, no Firestore Rules changes.
///
/// Dashboard counts fetch full snapshots rather than Firestore's count()
/// aggregation, since this repo slice doesn't include pubspec.yaml and the
/// pinned cloud_firestore version isn't known. Fine for an admin-only,
/// low-traffic foundation.
///
/// Ban/unban/disable delegate to the existing ProfileRepository.updateProfile
/// write path instead of writing to Firestore directly, so there is exactly
/// one place that writes to a user document.
class AdminRepositoryImpl implements AdminRepository {
  final FirebaseFirestore firestore;
  final ProfileRepository profileRepository;

  const AdminRepositoryImpl({required this.firestore, required this.profileRepository});

  @override
  Future<Either<Failure, AdminDashboardStats>> getDashboardStats() async {
    try {
      final usersSnapshot = await firestore.collection('users').get();
      final chatsSnapshot = await firestore.collection('chats').get();
      final friendsSnapshot = await firestore.collectionGroup('friends').get();

      final totalGroups = chatsSnapshot.docs.where((d) => d.data().containsKey('adminIds')).length;
      final totalChats = chatsSnapshot.docs.length - totalGroups;

      return Right(AdminDashboardStats(
        totalUsers: usersSnapshot.docs.length,
        totalFriends: friendsSnapshot.docs.length,
        totalChats: totalChats,
        totalGroups: totalGroups,
      ));
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, AdminUserRecord?>> lookupUserByUid(String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return const Right(null);
    try {
      final doc = await firestore.collection('users').doc(trimmed).get();
      final data = doc.data();
      if (!doc.exists || data == null) return const Right(null);
      return Right(_toRecord(trimmed, data));
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<AdminUserRecord>>> lookupUsersByUsername(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const Right(<AdminUserRecord>[]);
    try {
      final snapshot = await firestore
          .collection('users')
          .orderBy('username')
          .startAt([trimmed])
          .endAt(['$trimmed\uf8ff'])
          .limit(20)
          .get();
      return Right(snapshot.docs.map((d) => _toRecord(d.id, d.data())).toList());
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  AdminUserRecord _toRecord(String uid, Map<String, dynamic> data) {
    final expiresAtRaw = data['banExpiresAt'];
    return AdminUserRecord(
      profile: ProfileModel.fromJson(uid, data),
      isBanned: data['isBanned'] as bool? ?? false,
      isDisabled: data['isDisabled'] as bool? ?? false,
      banType: data['banType'] != null ? banTypeFromString(data['banType'] as String?) : null,
      banExpiresAt: expiresAtRaw is Timestamp ? expiresAtRaw.toDate() : null,
    );
  }

  // Phase 8.6C (Ban System)
  //
  // Reuses ProfileRepository.updateProfile as the single write path for the
  // moderation flags on the user doc (same as 8.6A). Adds a 'bans' top-level
  // collection (same pattern as 'reports'/'warnings' from 8.6B) so ban
  // history survives beyond the current isBanned flag, and threads
  // actorUid through to _logAction for every ban/unban/disable/restore.

  CollectionReference<Map<String, dynamic>> get _bansCollection => firestore.collection('bans');

  @override
  Future<Either<Failure, void>> banUser({
    required String targetUid,
    required String reason,
    required String issuedBy,
    required BanType type,
    DateTime? expiresAt,
  }) async {
    try {
      await _bansCollection.add({
        'targetUid': targetUid,
        'reason': reason,
        'issuedBy': issuedBy,
        'timestamp': FieldValue.serverTimestamp(),
        'status': banStatusToString(BanStatus.active),
        'type': banTypeToString(type),
        'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
      });
      final updates = <String, dynamic>{
        'isBanned': true,
        'bannedAt': FieldValue.serverTimestamp(),
        'banType': banTypeToString(type),
        'banExpiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt) : FieldValue.delete(),
      };
      await profileRepository.updateProfile(uid: targetUid, updates: updates);
      await _logAction(action: 'ban', actorUid: issuedBy, targetUid: targetUid, details: reason);
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> unbanUser({
    required String targetUid,
    required String issuedBy,
  }) async {
    try {
      final activeBans = await _bansCollection
          .where('targetUid', isEqualTo: targetUid)
          .where('status', isEqualTo: banStatusToString(BanStatus.active))
          .get();
      for (final doc in activeBans.docs) {
        await doc.reference.update({'status': banStatusToString(BanStatus.lifted)});
      }
      await profileRepository.updateProfile(uid: targetUid, updates: {
        'isBanned': false,
        'bannedAt': FieldValue.delete(),
        'banType': FieldValue.delete(),
        'banExpiresAt': FieldValue.delete(),
      });
      await _logAction(action: 'unban', actorUid: issuedBy, targetUid: targetUid);
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> disableAccount({
    required String targetUid,
    required String issuedBy,
  }) async {
    try {
      await profileRepository.updateProfile(uid: targetUid, updates: {
        'isDisabled': true,
        'disabledAt': FieldValue.serverTimestamp(),
      });
      await _logAction(action: 'disable', actorUid: issuedBy, targetUid: targetUid);
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> restoreAccount({
    required String targetUid,
    required String issuedBy,
  }) async {
    try {
      await profileRepository.updateProfile(uid: targetUid, updates: {
        'isDisabled': false,
        'disabledAt': FieldValue.delete(),
      });
      await _logAction(action: 'restore', actorUid: issuedBy, targetUid: targetUid);
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<BanRecord>>> getBanHistory(String targetUid) async {
    try {
      final snapshot = await _bansCollection.where('targetUid', isEqualTo: targetUid).get();
      final records = snapshot.docs.map((doc) {
        final data = doc.data();
        final ts = data['timestamp'];
        final expiresAtRaw = data['expiresAt'];
        return BanRecord(
          banId: doc.id,
          targetUid: data['targetUid'] as String? ?? '',
          reason: data['reason'] as String? ?? '',
          issuedBy: data['issuedBy'] as String? ?? '',
          timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
          status: banStatusFromString(data['status'] as String?),
          type: banTypeFromString(data['type'] as String?),
          expiresAt: expiresAtRaw is Timestamp ? expiresAtRaw.toDate() : null,
        );
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(records);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  // Phase 8.6B (Moderation System)
  //
  // Reuses this repository (already the single write path for moderation
  // flags) instead of introducing a parallel repository. Two new top-level
  // collections are added — 'reports' and 'warnings' — plus 'adminActionLog'
  // for tracking. No Cloud Functions, no Firestore Rules changes.

  CollectionReference<Map<String, dynamic>> get _reportsCollection => firestore.collection('reports');

  CollectionReference<Map<String, dynamic>> get _warningsCollection => firestore.collection('warnings');

  CollectionReference<Map<String, dynamic>> get _actionLogCollection => firestore.collection('adminActionLog');

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
      await _reportsCollection.add({
        'type': reportTypeToString(type),
        'reporterUid': reporterUid,
        'targetUid': targetUid,
        'messageId': messageId,
        'chatId': chatId,
        'groupId': groupId,
        'reason': reason,
        'description': description,
        'timestamp': FieldValue.serverTimestamp(),
        'status': reportStatusToString(ReportStatus.pending),
      });
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
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
    return _submitReport(
      type: ReportType.group,
      reporterUid: reporterUid,
      reason: reason,
      groupId: groupId,
    );
  }

  @override
  Future<Either<Failure, List<ModerationReport>>> getModerationReports() async {
    try {
      final snapshot = await _reportsCollection.get();
      final reports = snapshot.docs.map(_toReport).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(reports);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  ModerationReport _toReport(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final ts = data['timestamp'];
    return ModerationReport(
      reportId: doc.id,
      type: reportTypeFromString(data['type'] as String?),
      reporterUid: data['reporterUid'] as String? ?? '',
      targetUid: data['targetUid'] as String?,
      messageId: data['messageId'] as String?,
      chatId: data['chatId'] as String?,
      groupId: data['groupId'] as String?,
      reason: data['reason'] as String? ?? '',
      description: data['description'] as String?,
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      status: reportStatusFromString(data['status'] as String?),
    );
  }

  @override
  Future<Either<Failure, void>> updateReportStatus({
    required String reportId,
    required ReportStatus status,
    required String adminUid,
  }) async {
    try {
      final reportRef = _reportsCollection.doc(reportId);
      await reportRef.update({'status': reportStatusToString(status)});
      await _logAction(
        action: status == ReportStatus.resolved ? 'report_resolved' : 'report_reviewed',
        actorUid: adminUid,
        reportId: reportId,
      );
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> issueWarning({
    required String userUid,
    required String reason,
    required String issuedBy,
  }) async {
    try {
      await _warningsCollection.add({
        'userUid': userUid,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'issuedBy': issuedBy,
      });
      await _logAction(
        action: 'warning_issued',
        actorUid: issuedBy,
        targetUid: userUid,
        details: reason,
      );
      return const Right(null);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<UserWarning>>> getUserWarnings(String userUid) async {
    try {
      final snapshot = await _warningsCollection.where('userUid', isEqualTo: userUid).get();
      final warnings = snapshot.docs.map((doc) {
        final data = doc.data();
        final ts = data['timestamp'];
        return UserWarning(
          warningId: doc.id,
          userUid: data['userUid'] as String? ?? '',
          reason: data['reason'] as String? ?? '',
          timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
          issuedBy: data['issuedBy'] as String? ?? '',
        );
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(warnings);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }

  Future<void> _logAction({
    required String action,
    required String actorUid,
    String? targetUid,
    String? reportId,
    String? details,
  }) {
    return _actionLogCollection.add({
      'action': action,
      'actorUid': actorUid,
      'targetUid': targetUid,
      'reportId': reportId,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<Either<Failure, List<AdminActionLogEntry>>> getActionLog() async {
    try {
      final snapshot = await _actionLogCollection.get();
      final entries = snapshot.docs.map((doc) {
        final data = doc.data();
        final ts = data['timestamp'];
        return AdminActionLogEntry(
          logId: doc.id,
          action: data['action'] as String? ?? '',
          actorUid: data['actorUid'] as String? ?? '',
          targetUid: data['targetUid'] as String?,
          reportId: data['reportId'] as String?,
          details: data['details'] as String?,
          timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
        );
      }).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(entries);
    } catch (e) {
      return Left(FirebaseFailure(e.toString()));
    }
  }
}
