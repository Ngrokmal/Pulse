import '../../../../core/utils/moderation_guard.dart';
import '../entities/app_settings.dart';
import '../entities/privacy_settings.dart';
import '../repositories/profile_repository.dart';

class UpdateProfileUseCase {
  final ProfileRepository repository;
  final ModerationGuard moderationGuard;
  const UpdateProfileUseCase(this.repository, this.moderationGuard);

  Future<void> call({
    required String uid,
    String? displayName,
    String? username,
    String? bio,
    String? location,
    String? gender,
    DateTime? birthday,
    String? phone,
    String? email,
    String? website,
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
  }) async {
    await moderationGuard.ensureNotBlocked(uid);

    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (username != null) updates['username'] = username;
    if (bio != null) updates['bio'] = bio;
    if (location != null) updates['location'] = location;
    if (gender != null) updates['gender'] = gender;
    if (birthday != null) updates['birthday'] = birthday;
    if (phone != null) updates['phone'] = phone;
    if (email != null) updates['email'] = email;
    if (website != null) updates['website'] = website;
    if (notificationsEnabled != null) updates['notificationsEnabled'] = notificationsEnabled;
    if (profilePrivacy != null) updates['profilePrivacy'] = privacyOptionToString(profilePrivacy);
    if (lastSeenVisibility != null) updates['lastSeenVisibility'] = privacyOptionToString(lastSeenVisibility);
    if (onlineStatusVisibility != null) {
      updates['onlineStatusVisibility'] = privacyOptionToString(onlineStatusVisibility);
    }
    if (friendRequestPrivacy != null) {
      updates['friendRequestPrivacy'] = friendRequestPrivacyToString(friendRequestPrivacy);
    }
    if (themeMode != null) updates['themeMode'] = appThemeModePrefToString(themeMode);
    if (enterToSend != null) updates['enterToSend'] = enterToSend;
    if (readReceiptsEnabled != null) updates['readReceiptsEnabled'] = readReceiptsEnabled;
    if (typingIndicatorEnabled != null) updates['typingIndicatorEnabled'] = typingIndicatorEnabled;
    if (autoDownloadImages != null) updates['autoDownloadImages'] = autoDownloadImages;
    if (autoDownloadVideos != null) updates['autoDownloadVideos'] = autoDownloadVideos;
    if (autoDownloadFiles != null) updates['autoDownloadFiles'] = autoDownloadFiles;
    if (mediaWifiOnly != null) updates['mediaWifiOnly'] = mediaWifiOnly;

    return repository.updateProfile(uid: uid, updates: updates);
  }
}
