import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/entities/verification_status.dart';

class ProfileModel extends ProfileEntity {
  const ProfileModel({
    required super.uid,
    required super.username,
    required super.displayName,
    super.bio,
    super.location,
    super.gender,
    super.birthday,
    super.phone,
    super.email,
    super.website,
    super.isOnline,
    super.lastSeen,
    super.avatarUrl,
    super.avatarPublicId,
    super.coverUrl,
    super.coverPublicId,
    super.friendsCount,
    super.groupsCount,
    super.verificationStatus,
    super.createdAt,
    super.notificationsEnabled,
    super.profilePrivacy,
    super.lastSeenVisibility,
    super.onlineStatusVisibility,
    super.friendRequestPrivacy,
    super.themeMode,
    super.enterToSend,
    super.readReceiptsEnabled,
    super.typingIndicatorEnabled,
    super.autoDownloadImages,
    super.autoDownloadVideos,
    super.autoDownloadFiles,
    super.mediaWifiOnly,
  });

  factory ProfileModel.fromJson(String uid, Map<String, dynamic> json) {
    final Timestamp? birthdayTs = json['birthday'] as Timestamp?;
    final Timestamp? lastSeenTs = json['lastSeen'] as Timestamp?;
    final Timestamp? createdAtTs = json['createdAt'] as Timestamp?;

    return ProfileModel(
      uid: uid,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String?,
      location: json['location'] as String?,
      gender: json['gender'] as String?,
      birthday: birthdayTs?.toDate(),
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      website: json['website'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: lastSeenTs?.toDate(),
      avatarUrl: json['avatarUrl'] as String?,
      avatarPublicId: json['avatarPublicId'] as String?,
      coverUrl: json['coverUrl'] as String?,
      coverPublicId: json['coverPublicId'] as String?,
      friendsCount: json['friendsCount'] as int? ?? 0,
      groupsCount: json['groupsCount'] as int? ?? 0,
      verificationStatus: verificationStatusFromString(json['verificationStatus'] as String?),
      createdAt: createdAtTs?.toDate(),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      profilePrivacy: privacyOptionFromString(json['profilePrivacy'] as String?),
      lastSeenVisibility: privacyOptionFromString(json['lastSeenVisibility'] as String?),
      onlineStatusVisibility: privacyOptionFromString(json['onlineStatusVisibility'] as String?),
      friendRequestPrivacy: friendRequestPrivacyFromString(json['friendRequestPrivacy'] as String?),
      themeMode: appThemeModePrefFromString(json['themeMode'] as String?),
      enterToSend: json['enterToSend'] as bool? ?? true,
      readReceiptsEnabled: json['readReceiptsEnabled'] as bool? ?? true,
      typingIndicatorEnabled: json['typingIndicatorEnabled'] as bool? ?? true,
      autoDownloadImages: json['autoDownloadImages'] as bool? ?? true,
      autoDownloadVideos: json['autoDownloadVideos'] as bool? ?? false,
      autoDownloadFiles: json['autoDownloadFiles'] as bool? ?? false,
      mediaWifiOnly: json['mediaWifiOnly'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'uid': uid,
      'username': username,
      'displayName': displayName,
      'bio': bio,
      'isOnline': isOnline,
      'friendsCount': friendsCount,
      'groupsCount': groupsCount,
      'verificationStatus': verificationStatusToString(verificationStatus),
      'createdAt': FieldValue.serverTimestamp(),
      'notificationsEnabled': notificationsEnabled,
      'profilePrivacy': privacyOptionToString(profilePrivacy),
      'lastSeenVisibility': privacyOptionToString(lastSeenVisibility),
      'onlineStatusVisibility': privacyOptionToString(onlineStatusVisibility),
      'friendRequestPrivacy': friendRequestPrivacyToString(friendRequestPrivacy),
      'themeMode': appThemeModePrefToString(themeMode),
      'enterToSend': enterToSend,
      'readReceiptsEnabled': readReceiptsEnabled,
      'typingIndicatorEnabled': typingIndicatorEnabled,
      'autoDownloadImages': autoDownloadImages,
      'autoDownloadVideos': autoDownloadVideos,
      'autoDownloadFiles': autoDownloadFiles,
      'mediaWifiOnly': mediaWifiOnly,
    };
  }
}
