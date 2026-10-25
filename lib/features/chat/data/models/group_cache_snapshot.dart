library group_cache_snapshot;

class CachedGroupSnapshot {
  final String groupId;
  final String name;
  final String creatorId;
  final DateTime createdAt;
  final String? groupPhotoUrl;
  final String? groupPhotoPublicId;

  const CachedGroupSnapshot({
    required this.groupId,
    required this.name,
    required this.creatorId,
    required this.createdAt,
    this.groupPhotoUrl,
    this.groupPhotoPublicId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedGroupSnapshot &&
          other.groupId == groupId &&
          other.name == name &&
          other.creatorId == creatorId &&
          other.createdAt == createdAt &&
          other.groupPhotoUrl == groupPhotoUrl &&
          other.groupPhotoPublicId == groupPhotoPublicId);

  @override
  int get hashCode => Object.hash(groupId, name, creatorId, createdAt, groupPhotoUrl, groupPhotoPublicId);
}

class CachedMemberSnapshot {
  final String userId;
  final String? firebaseUid;
  final String role;
  final bool hasLeft;

  const CachedMemberSnapshot({
    required this.userId,
    required this.firebaseUid,
    required this.role,
    required this.hasLeft,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMemberSnapshot &&
          other.userId == userId &&
          other.firebaseUid == firebaseUid &&
          other.role == role &&
          other.hasLeft == hasLeft);

  @override
  int get hashCode => Object.hash(userId, firebaseUid, role, hasLeft);
}
