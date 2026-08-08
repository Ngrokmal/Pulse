import '../../../../core/services/local_db_service.dart';
import '../../domain/entities/group_entity.dart';
import '../models/group_cache_snapshot.dart';

abstract class GroupInfoLocalDataSource {
  Future<GroupEntity?> getCachedGroup(String groupId);

  Future<void> upsertGroupBase(String groupId, GroupEntity group);

  Future<DateTime?> getGroupInfoCursor(String groupId);
  Future<void> setGroupInfoCursor(String groupId, DateTime time);

  Future<void> upsertMembers(String groupId, List<Map<String, dynamic>> memberRows);

  Future<DateTime?> getMembersCursor(String groupId);
  Future<void> setMembersCursor(String groupId, DateTime time);

  Future<GroupEntity?> rebuildGroupEntityFromCache(String groupId);
}

class GroupInfoLocalDataSourceImpl implements GroupInfoLocalDataSource {
  final Map<String, CachedGroupSnapshot> _memGroupCache = {};
  final Map<String, Map<String, CachedMemberSnapshot>> _memMembersCache = {};

  CachedGroupSnapshot _snapshotFromEntity(GroupEntity g) => CachedGroupSnapshot(
        groupId: g.groupId,
        name: g.name,
        creatorId: g.creatorId,
        createdAt: g.createdAt,
        groupPhotoUrl: g.groupPhotoUrl,
        groupPhotoPublicId: g.groupPhotoPublicId,
      );

  CachedMemberSnapshot _snapshotFromRow(Map<String, dynamic> row) => CachedMemberSnapshot(
        userId: row['user_id'] as String,
        firebaseUid: row['firebase_uid'] as String?,
        role: row['role'] as String? ?? 'member',
        hasLeft: row['left_at'] != null,
      );

  Map<String, dynamic> _entityToJson(GroupEntity g) => {
        'groupId': g.groupId,
        'name': g.name,
        'creatorId': g.creatorId,
        'createdAt': g.createdAt.millisecondsSinceEpoch,
        if (g.groupPhotoUrl != null) 'groupPhotoUrl': g.groupPhotoUrl,
        if (g.groupPhotoPublicId != null) 'groupPhotoPublicId': g.groupPhotoPublicId,
      };

  GroupEntity _entityFromMemory(String groupId) {
    final base = _memGroupCache[groupId]!;
    final members = _memMembersCache[groupId] ?? const {};
    final memberUids = <String>[];
    final adminUids = <String>[];
    for (final snapshot in members.values) {
      if (snapshot.hasLeft) continue;
      final firebaseUid = snapshot.firebaseUid;
      if (firebaseUid == null) continue;
      memberUids.add(firebaseUid);
      if (snapshot.role == 'admin') adminUids.add(firebaseUid);
    }
    return GroupEntity(
      groupId: base.groupId,
      name: base.name,
      creatorId: base.creatorId,
      cachedMemberUids: memberUids,
      adminIds: adminUids,
      createdAt: base.createdAt,
      groupPhotoUrl: base.groupPhotoUrl,
      groupPhotoPublicId: base.groupPhotoPublicId,
    );
  }

  @override
  Future<GroupEntity?> getCachedGroup(String groupId) async {
    if (_memGroupCache.containsKey(groupId)) {
      return _entityFromMemory(groupId);
    }
    return rebuildGroupEntityFromCache(groupId);
  }

  @override
  Future<void> upsertGroupBase(String groupId, GroupEntity group) async {
    final box = await LocalDbService.groupInfoBox();
    await box.put(groupId, _entityToJson(group));
    _memGroupCache[groupId] = _snapshotFromEntity(group);
  }

  @override
  Future<DateTime?> getGroupInfoCursor(String groupId) async {
    final box = await LocalDbService.syncMetaBox();
    final millis = box.get('groupInfoSyncedAt_$groupId') as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  @override
  Future<void> setGroupInfoCursor(String groupId, DateTime time) async {
    final box = await LocalDbService.syncMetaBox();
    final key = 'groupInfoSyncedAt_$groupId';
    final existing = box.get(key) as int?;
    final millis = time.millisecondsSinceEpoch;
    if (existing == null || millis > existing) {
      await box.put(key, millis);
    }
  }

  @override
  Future<void> upsertMembers(String groupId, List<Map<String, dynamic>> memberRows) async {
    if (memberRows.isEmpty) return;
    final box = await LocalDbService.groupMembersBox(groupId);
    final memMap = _memMembersCache.putIfAbsent(groupId, () => {});
    for (final row in memberRows) {
      final userId = row['user_id'] as String?;
      if (userId == null) continue;
      await box.put(userId, row);
      memMap[userId] = _snapshotFromRow(row);
    }
  }

  @override
  Future<DateTime?> getMembersCursor(String groupId) async {
    final box = await LocalDbService.syncMetaBox();
    final millis = box.get('groupMembersSyncedAt_$groupId') as int?;
    return millis != null ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }

  @override
  Future<void> setMembersCursor(String groupId, DateTime time) async {
    final box = await LocalDbService.syncMetaBox();
    final key = 'groupMembersSyncedAt_$groupId';
    final existing = box.get(key) as int?;
    final millis = time.millisecondsSinceEpoch;
    if (existing == null || millis > existing) {
      await box.put(key, millis);
    }
  }

  @override
  Future<GroupEntity?> rebuildGroupEntityFromCache(String groupId) async {
    final infoBox = await LocalDbService.groupInfoBox();
    final raw = infoBox.get(groupId);
    if (raw == null) return null;
    final json = Map<String, dynamic>.from(raw);

    final membersBox = await LocalDbService.groupMembersBox(groupId);
    final memMap = <String, CachedMemberSnapshot>{};
    for (final key in membersBox.keys) {
      final userId = key as String;
      final rawMember = membersBox.get(key);
      if (rawMember == null) continue;
      final row = Map<String, dynamic>.from(rawMember);
      row['user_id'] = row['user_id'] ?? userId;
      memMap[userId] = _snapshotFromRow(row);
    }

    final base = CachedGroupSnapshot(
      groupId: json['groupId'] as String? ?? groupId,
      name: json['name'] as String? ?? '',
      creatorId: json['creatorId'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      groupPhotoUrl: json['groupPhotoUrl'] as String?,
      groupPhotoPublicId: json['groupPhotoPublicId'] as String?,
    );

    _memGroupCache[groupId] = base;
    _memMembersCache[groupId] = memMap;

    return _entityFromMemory(groupId);
  }
}
