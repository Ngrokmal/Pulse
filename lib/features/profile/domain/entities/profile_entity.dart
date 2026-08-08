import 'app_settings.dart';
import 'privacy_settings.dart';
import 'verification_status.dart';

class ProfileEntity {
  final String uid;
  final String username;
  final String displayName;
  final String? bio;
  final String? location;
  final String? gender;
  final DateTime? birthday;
  final String? phone;
  final String? email;
  final String? website;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? avatarUrl;
  final String? avatarPublicId;
  final String? coverUrl;
  final String? coverPublicId;
  final int friendsCount;
  final int groupsCount;
  final VerificationStatus verificationStatus;
  final DateTime? createdAt;
  final bool notificationsEnabled;
  final PrivacyOption profilePrivacy;
  final PrivacyOption lastSeenVisibility;
  final PrivacyOption onlineStatusVisibility;
  final FriendRequestPrivacy friendRequestPrivacy;
  final AppThemeModePref themeMode;
  final bool enterToSend;
  final bool readReceiptsEnabled;
  final bool typingIndicatorEnabled;
  final bool autoDownloadImages;
  final bool autoDownloadVideos;
  final bool autoDownloadFiles;
  final bool mediaWifiOnly;

  const ProfileEntity({
    required this.uid,
    required this.username,
    required this.displayName,
    this.bio,
    this.location,
    this.gender,
    this.birthday,
    this.phone,
    this.email,
    this.website,
    this.isOnline = false,
    this.lastSeen,
    this.avatarUrl,
    this.avatarPublicId,
    this.coverUrl,
    this.coverPublicId,
    this.friendsCount = 0,
    this.groupsCount = 0,
    this.verificationStatus = VerificationStatus.notVerified,
    this.createdAt,
    this.notificationsEnabled = true,
    this.profilePrivacy = PrivacyOption.public,
    this.lastSeenVisibility = PrivacyOption.public,
    this.onlineStatusVisibility = PrivacyOption.public,
    this.friendRequestPrivacy = FriendRequestPrivacy.everyone,
    this.themeMode = AppThemeModePref.system,
    this.enterToSend = true,
    this.readReceiptsEnabled = true,
    this.typingIndicatorEnabled = true,
    this.autoDownloadImages = true,
    this.autoDownloadVideos = false,
    this.autoDownloadFiles = false,
    this.mediaWifiOnly = true,
  });

  ProfileEntity copyWith({
    String? username,
    String? displayName,
    String? bio,
    String? location,
    String? gender,
    DateTime? birthday,
    String? phone,
    String? email,
    String? website,
    bool? isOnline,
    DateTime? lastSeen,
    String? avatarUrl,
    String? avatarPublicId,
    String? coverUrl,
    String? coverPublicId,
    int? friendsCount,
    int? groupsCount,
    VerificationStatus? verificationStatus,
    bool? notificationsEnabled,
    PrivacyOption? profilePrivacy,
    PrivacyOption? lastSeenVisibility,
    PrivacyOption? onlineStatusVisibility,
    FriendRequestPrivacy? friendRequestPrivacy,
    AppThemeModePref? themeMode,
    bool? enterToSend,
    bool? readReceiptsEnabled,
    bool? typingIndicatorEnabled,
    bool? autoDownloadImages,
    bool? autoDownloadVideos,
    bool? autoDownloadFiles,
    bool? mediaWifiOnly,
  }) {
    return ProfileEntity(
      uid: uid,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      gender: gender ?? this.gender,
      birthday: birthday ?? this.birthday,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarPublicId: avatarPublicId ?? this.avatarPublicId,
      coverUrl: coverUrl ?? this.coverUrl,
      coverPublicId: coverPublicId ?? this.coverPublicId,
      friendsCount: friendsCount ?? this.friendsCount,
      groupsCount: groupsCount ?? this.groupsCount,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdAt: createdAt,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      profilePrivacy: profilePrivacy ?? this.profilePrivacy,
      lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
      onlineStatusVisibility: onlineStatusVisibility ?? this.onlineStatusVisibility,
      friendRequestPrivacy: friendRequestPrivacy ?? this.friendRequestPrivacy,
      themeMode: themeMode ?? this.themeMode,
      enterToSend: enterToSend ?? this.enterToSend,
      readReceiptsEnabled: readReceiptsEnabled ?? this.readReceiptsEnabled,
      typingIndicatorEnabled: typingIndicatorEnabled ?? this.typingIndicatorEnabled,
      autoDownloadImages: autoDownloadImages ?? this.autoDownloadImages,
      autoDownloadVideos: autoDownloadVideos ?? this.autoDownloadVideos,
      autoDownloadFiles: autoDownloadFiles ?? this.autoDownloadFiles,
      mediaWifiOnly: mediaWifiOnly ?? this.mediaWifiOnly,
    );
  }
}
