import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/entities/verification_status.dart';

class SearchCandidateModel extends ProfileEntity {
  final DateTime rowUpdatedAt;

  const SearchCandidateModel({
    required String uid,
    required String username,
    required String displayName,
    String? avatarUrl,
    VerificationStatus verificationStatus = VerificationStatus.notVerified,
    required this.rowUpdatedAt,
  }) : super(
          uid: uid,
          username: username,
          displayName: displayName,
          avatarUrl: avatarUrl,
          verificationStatus: verificationStatus,
        );

  factory SearchCandidateModel.fromSupabaseRow(
    Map<String, dynamic> row, {
    required String firebaseUid,
  }) {
    final dynamic rawUpdatedAt = row['updated_at'];
    final DateTime resolvedUpdatedAt = rawUpdatedAt is String
        ? DateTime.parse(rawUpdatedAt).toLocal()
        : DateTime.now();

    return SearchCandidateModel(
      uid: firebaseUid,
      username: row['username'] as String? ?? '',
      displayName: (row['display_name'] as String?) ?? '',
      avatarUrl: row['avatar_url'] as String?,
      verificationStatus: verificationStatusFromString(row['verification_status'] as String?),
      rowUpdatedAt: resolvedUpdatedAt,
    );
  }

  factory SearchCandidateModel.fromCacheJson(Map<String, dynamic> json) {
    return SearchCandidateModel(
      uid: json['uid'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      verificationStatus: verificationStatusFromString(json['verificationStatus'] as String?),
      rowUpdatedAt: DateTime.fromMillisecondsSinceEpoch(json['rowUpdatedAt'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'uid': uid,
      'username': username,
      'displayName': displayName,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'verificationStatus': verificationStatusToString(verificationStatus),
      'rowUpdatedAt': rowUpdatedAt.millisecondsSinceEpoch,
    };
  }
}
