import '../../domain/entities/profile_entity.dart';
import '../../domain/entities/verification_status.dart';

/// UI-ONLY placeholder model.
///
/// This is intentionally NOT a domain entity. It carries zero business
/// logic, has no relation to Bloc/Cubit/Repository/UseCases, and exists
/// purely so the Profile UI screens have something to render while the
/// real "Profile Logic" milestone (see HANDOFF.md → Remaining Priority)
/// is implemented later. When that milestone lands, screens can simply
/// swap `ProfileUiData.placeholder()` for real data mapped from the
/// domain entity — the widgets below never assume where the data came
/// from.
class ProfileUiData {
  final String uid;
  final String name;
  final String username;
  final String? bio;
  final String? location;
  final DateTime? joinDate;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? avatarUrl;
  final String? avatarPublicId;
  final String? coverUrl;
  final String? coverPublicId;
  final int mutualFriendsCount;
  final int sharedGroupsCount;
  final int mediaCount;
  final VerificationStatus verificationStatus;

  // Extra fields only relevant to the Edit Profile form.
  final String? gender;
  final DateTime? birthday;
  final String? phone;
  final String? email;
  final String? website;

  const ProfileUiData({
    this.uid = '',
    required this.name,
    required this.username,
    this.bio,
    this.location,
    this.joinDate,
    this.isOnline = false,
    this.lastSeen,
    this.avatarUrl,
    this.avatarPublicId,
    this.coverUrl,
    this.coverPublicId,
    this.mutualFriendsCount = 0,
    this.sharedGroupsCount = 0,
    this.mediaCount = 0,
    this.verificationStatus = VerificationStatus.notVerified,
    this.gender,
    this.birthday,
    this.phone,
    this.email,
    this.website,
  });

  factory ProfileUiData.fromEntity(
    ProfileEntity entity, {
    int? sharedGroupsCountOverride,
    int? mutualFriendsCountOverride,
  }) {
    return ProfileUiData(
      uid: entity.uid,
      name: entity.displayName.isNotEmpty ? entity.displayName : entity.username,
      username: entity.username.startsWith('@') ? entity.username : '@${entity.username}',
      bio: entity.bio,
      location: entity.location,
      joinDate: entity.createdAt,
      isOnline: entity.isOnline,
      lastSeen: entity.lastSeen,
      avatarUrl: entity.avatarUrl,
      avatarPublicId: entity.avatarPublicId,
      coverUrl: entity.coverUrl,
      coverPublicId: entity.coverPublicId,
      mutualFriendsCount: mutualFriendsCountOverride ?? entity.friendsCount,
      sharedGroupsCount: sharedGroupsCountOverride ?? entity.groupsCount,
      verificationStatus: entity.verificationStatus,
      gender: entity.gender,
      birthday: entity.birthday,
      phone: entity.phone,
      email: entity.email,
      website: entity.website,
    );
  }

  /// Sample data so every screen is fully explorable in isolation
  /// (design/QA review) without needing the real profile data source.
  factory ProfileUiData.placeholder({bool online = true}) {
    return ProfileUiData(
      name: 'Amelia Rahman',
      username: '@amelia.codes',
      bio: 'Product designer crafting delightful mobile experiences ✨ Coffee-powered.',
      location: 'Dhaka, Bangladesh',
      joinDate: DateTime(2023, 4, 12),
      isOnline: online,
      mutualFriendsCount: 12,
      sharedGroupsCount: 4,
      mediaCount: 128,
      gender: 'Female',
      birthday: DateTime(1998, 7, 22),
      phone: '+880 1XX-XXXXXXX',
      email: 'amelia@example.com',
      website: 'amelia.design',
    );
  }
}
