class GroupEntity {
  final String groupId;
  final String name;
  final String creatorId;
  final List<String> cachedMemberUids;
  final List<String> adminIds;
  final DateTime createdAt;
  final String? groupPhotoUrl;
  final String? groupPhotoPublicId;

  const GroupEntity({
    required this.groupId,
    required this.name,
    required this.creatorId,
    required this.cachedMemberUids,
    required this.adminIds,
    required this.createdAt,
    this.groupPhotoUrl,
    this.groupPhotoPublicId,
  });

  bool isAdmin(String uid) => adminIds.contains(uid) || uid == creatorId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupEntity &&
          other.groupId == groupId &&
          other.name == name &&
          other.creatorId == creatorId &&
          other.createdAt == createdAt &&
          other.groupPhotoUrl == groupPhotoUrl &&
          other.groupPhotoPublicId == groupPhotoPublicId &&
          _listEquals(other.cachedMemberUids, cachedMemberUids) &&
          _listEquals(other.adminIds, adminIds));

  @override
  int get hashCode => Object.hash(
        groupId,
        name,
        creatorId,
        createdAt,
        groupPhotoUrl,
        groupPhotoPublicId,
        Object.hashAll(cachedMemberUids),
        Object.hashAll(adminIds),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
