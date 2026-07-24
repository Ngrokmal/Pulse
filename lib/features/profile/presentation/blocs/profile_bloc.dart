import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../core/services/friend_profile_cache_service.dart';
import '../../../../core/theme/app_theme_controller.dart';
import '../../../chat/domain/repositories/media_repository.dart';
import '../../../chat/domain/usecases/get_or_create_direct_chat_usecase.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/friend_request_status.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/entities/profile_entity.dart';
import '../../domain/entities/profile_visibility.dart';
import '../../domain/usecases/accept_friend_request_usecase.dart';
import '../../domain/usecases/block_user_usecase.dart';
import '../../domain/usecases/cancel_friend_request_usecase.dart';
import '../../domain/usecases/delete_cover_photo_usecase.dart';
import '../../domain/usecases/delete_profile_photo_usecase.dart';
import '../../domain/usecases/ensure_profile_exists_usecase.dart';
import '../../domain/usecases/get_blocked_users_usecase.dart';
import '../../domain/usecases/get_friend_request_status_usecase.dart';
import '../../domain/usecases/get_mutual_friends_count_usecase.dart';
import '../../domain/usecases/get_mutual_groups_count_usecase.dart';
import '../../domain/usecases/get_relationship_status_usecase.dart';
import '../../domain/usecases/reject_friend_request_usecase.dart';
import '../../domain/usecases/send_friend_request_usecase.dart';
import '../../domain/usecases/stream_profile_usecase.dart';
import '../../domain/usecases/unblock_user_usecase.dart';
import '../../domain/usecases/unfriend_usecase.dart';
import '../../domain/usecases/update_cover_photo_usecase.dart';
import '../../domain/usecases/update_profile_photo_usecase.dart';
import '../../domain/usecases/update_profile_usecase.dart';
import '../../domain/usecases/upload_cover_photo_usecase.dart';
import '../../domain/usecases/upload_profile_photo_usecase.dart';

const _kLoadTimeout = Duration(seconds: 15);
const _kActionTimeout = Duration(seconds: 20);

enum PhotoSlot { avatar, cover }

enum PhotoUploadStage { idle, uploading, failed, cancelled }

class PhotoUploadStatus {
  final PhotoUploadStage stage;
  final double progress;
  final File? pendingFile;

  const PhotoUploadStatus({this.stage = PhotoUploadStage.idle, this.progress = 0, this.pendingFile});

  bool get isBusy => stage == PhotoUploadStage.uploading;
}

abstract class ProfileEvent {}

class LoadProfileEvent extends ProfileEvent {
  final String uid;
  final String viewerUid;
  LoadProfileEvent({required this.uid, required this.viewerUid});
}

class UpdateProfileRequested extends ProfileEvent {
  final String uid;
  final String? displayName;
  final String? username;
  final String? bio;
  final String? location;
  final String? gender;
  final DateTime? birthday;
  final String? phone;
  final String? email;
  final String? website;
  UpdateProfileRequested({
    required this.uid,
    this.displayName,
    this.username,
    this.bio,
    this.location,
    this.gender,
    this.birthday,
    this.phone,
    this.email,
    this.website,
  });
}

class UpdatePhotoRequested extends ProfileEvent {
  final String uid;
  final PhotoSlot slot;
  final File file;
  UpdatePhotoRequested({required this.uid, required this.slot, required this.file});
}

class RetryPhotoUploadRequested extends ProfileEvent {
  final String uid;
  final PhotoSlot slot;
  RetryPhotoUploadRequested({required this.uid, required this.slot});
}

class CancelPhotoUploadRequested extends ProfileEvent {
  final PhotoSlot slot;
  CancelPhotoUploadRequested({required this.slot});
}

class RemovePhotoRequested extends ProfileEvent {
  final String uid;
  final PhotoSlot slot;
  RemovePhotoRequested({required this.uid, required this.slot});
}

class SendFriendRequestRequested extends ProfileEvent {
  final String fromUid;
  final String toUid;
  SendFriendRequestRequested({required this.fromUid, required this.toUid});
}

class CancelFriendRequestRequested extends ProfileEvent {
  final String uid;
  final String targetUid;
  CancelFriendRequestRequested({required this.uid, required this.targetUid});
}

class AcceptFriendRequestRequested extends ProfileEvent {
  final String uid;
  final String requesterUid;
  AcceptFriendRequestRequested({required this.uid, required this.requesterUid});
}

class RejectFriendRequestRequested extends ProfileEvent {
  final String uid;
  final String requesterUid;
  RejectFriendRequestRequested({required this.uid, required this.requesterUid});
}

class UnfriendRequested extends ProfileEvent {
  final String uid;
  final String targetUid;
  UnfriendRequested({required this.uid, required this.targetUid});
}

class BlockUserRequested extends ProfileEvent {
  final String uid;
  final String targetUid;
  BlockUserRequested({required this.uid, required this.targetUid});
}

class UnblockUserRequested extends ProfileEvent {
  final String uid;
  final String targetUid;
  UnblockUserRequested({required this.uid, required this.targetUid});
}

class UpdateSettingsRequested extends ProfileEvent {
  final String uid;
  final bool? notificationsEnabled;
  final PrivacyOption? profilePrivacy;
  final PrivacyOption? lastSeenVisibility;
  final PrivacyOption? onlineStatusVisibility;
  final FriendRequestPrivacy? friendRequestPrivacy;
  final AppThemeModePref? themeMode;
  final bool? enterToSend;
  final bool? readReceiptsEnabled;
  final bool? typingIndicatorEnabled;
  final bool? autoDownloadImages;
  final bool? autoDownloadVideos;
  final bool? autoDownloadFiles;
  final bool? mediaWifiOnly;
  UpdateSettingsRequested({
    required this.uid,
    this.notificationsEnabled,
    this.profilePrivacy,
    this.lastSeenVisibility,
    this.onlineStatusVisibility,
    this.friendRequestPrivacy,
    this.themeMode,
    this.enterToSend,
    this.readReceiptsEnabled,
    this.typingIndicatorEnabled,
    this.autoDownloadImages,
    this.autoDownloadVideos,
    this.autoDownloadFiles,
    this.mediaWifiOnly,
  });
}

class LoadBlockedUsersRequested extends ProfileEvent {
  final String uid;
  LoadBlockedUsersRequested({required this.uid});
}

class UnblockUserFromSettingsRequested extends ProfileEvent {
  final String uid;
  final String targetUid;
  UnblockUserFromSettingsRequested({required this.uid, required this.targetUid});
}

class _ProfileSnapshotReceived extends ProfileEvent {
  final ProfileEntity profile;
  _ProfileSnapshotReceived(this.profile);
}

class _ProfileStreamErrored extends ProfileEvent {
  final String message;
  _ProfileStreamErrored(this.message);
}

class _ProfileLoadTimedOut extends ProfileEvent {}

abstract class ProfileState {}

class ProfileInitial extends ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoadedState extends ProfileState {
  final ProfileEntity profile;
  final ProfileVisibility visibility;
  final bool isSaving;
  final PhotoUploadStatus avatarUpload;
  final PhotoUploadStatus coverUpload;
  final int? mutualGroupsCount;
  final int? mutualFriendsCount;
  final FriendRequestStatus friendRequestStatus;
  final bool isFriendActionPending;
  final List<String>? blockedUserIds;

  ProfileLoadedState({
    required this.profile,
    this.visibility = ProfileVisibility.owner,
    this.isSaving = false,
    this.avatarUpload = const PhotoUploadStatus(),
    this.coverUpload = const PhotoUploadStatus(),
    this.mutualGroupsCount,
    this.mutualFriendsCount,
    this.friendRequestStatus = FriendRequestStatus.notFriends,
    this.isFriendActionPending = false,
    this.blockedUserIds,
  });

  ProfileLoadedState copyWith({
    ProfileEntity? profile,
    ProfileVisibility? visibility,
    bool? isSaving,
    PhotoUploadStatus? avatarUpload,
    PhotoUploadStatus? coverUpload,
    int? mutualGroupsCount,
    int? mutualFriendsCount,
    FriendRequestStatus? friendRequestStatus,
    bool? isFriendActionPending,
    List<String>? blockedUserIds,
  }) {
    return ProfileLoadedState(
      profile: profile ?? this.profile,
      visibility: visibility ?? this.visibility,
      isSaving: isSaving ?? this.isSaving,
      avatarUpload: avatarUpload ?? this.avatarUpload,
      coverUpload: coverUpload ?? this.coverUpload,
      mutualGroupsCount: mutualGroupsCount ?? this.mutualGroupsCount,
      mutualFriendsCount: mutualFriendsCount ?? this.mutualFriendsCount,
      friendRequestStatus: friendRequestStatus ?? this.friendRequestStatus,
      isFriendActionPending: isFriendActionPending ?? this.isFriendActionPending,
      blockedUserIds: blockedUserIds ?? this.blockedUserIds,
    );
  }
}

class ProfileErrorState extends ProfileState {
  final String message;
  ProfileErrorState({required this.message});
}

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final StreamProfileUseCase streamProfileUseCase;
  final EnsureProfileExistsUseCase ensureProfileExistsUseCase;
  final UpdateProfileUseCase updateProfileUseCase;
  final UploadProfilePhotoUseCase uploadProfilePhotoUseCase;
  final UpdateProfilePhotoUseCase updateProfilePhotoUseCase;
  final DeleteProfilePhotoUseCase deleteProfilePhotoUseCase;
  final UploadCoverPhotoUseCase uploadCoverPhotoUseCase;
  final UpdateCoverPhotoUseCase updateCoverPhotoUseCase;
  final DeleteCoverPhotoUseCase deleteCoverPhotoUseCase;
  final GetRelationshipStatusUseCase getRelationshipStatusUseCase;
  final GetMutualGroupsCountUseCase getMutualGroupsCountUseCase;
  final GetMutualFriendsCountUseCase getMutualFriendsCountUseCase;
  final GetFriendRequestStatusUseCase getFriendRequestStatusUseCase;
  final SendFriendRequestUseCase sendFriendRequestUseCase;
  final CancelFriendRequestUseCase cancelFriendRequestUseCase;
  final AcceptFriendRequestUseCase acceptFriendRequestUseCase;
  final RejectFriendRequestUseCase rejectFriendRequestUseCase;
  final UnfriendUseCase unfriendUseCase;
  final BlockUserUseCase blockUserUseCase;
  final UnblockUserUseCase unblockUserUseCase;
  final GetBlockedUsersUseCase getBlockedUsersUseCase;
  final MediaRepository mediaRepository;
  // Friend → Chat lifecycle fix: reuses the exact same use case
  // FriendProfileScreen/NonFriendProfileScreen already use for the
  // "Message" button (GetOrCreateDirectChatUseCase → ChatRepository.
  // ensureDirectChatExists). No duplicate chat-creation logic, no service
  // locator inside a repository — this is a normal constructor-injected
  // dependency on a presentation-layer bloc, same DI pattern as every other
  // use case field above.
  final GetOrCreateDirectChatUseCase getOrCreateDirectChatUseCase;

  ProfileEntity? _currentProfile;
  ProfileVisibility _currentVisibility = ProfileVisibility.owner;
  Timer? _loadTimeoutTimer;
  int _avatarUploadToken = 0;
  int _coverUploadToken = 0;
  StreamSubscription<ProfileEntity>? _profileSubscription;
  bool _firstSnapshotReceived = false;
  String? _viewerUid;
  String? _profileUid;
  String? _extraDetailsLoadedFor;

  // FIX 2 (My Profile open must never perform a hidden Firestore write):
  // ensureProfileExistsUseCase does a Firestore `.get()` + conditional
  // `.set()` and was previously called on *every* LoadProfileEvent for
  // uid == viewerUid (i.e. every My Profile open). Signup already creates
  // users/{uid} atomically (auth_remote_datasource.dart), so this was pure
  // safety-net code — kept, but now gated to fire at most once per app
  // session (static, since ProfileBloc is a DI factory — a new instance is
  // created per screen open, so an instance field would not remember
  // across repeat opens).
  static final Set<String> _ensuredExistsUids = <String>{};

  ProfileBloc({
    required this.streamProfileUseCase,
    required this.ensureProfileExistsUseCase,
    required this.updateProfileUseCase,
    required this.uploadProfilePhotoUseCase,
    required this.updateProfilePhotoUseCase,
    required this.deleteProfilePhotoUseCase,
    required this.uploadCoverPhotoUseCase,
    required this.updateCoverPhotoUseCase,
    required this.deleteCoverPhotoUseCase,
    required this.getRelationshipStatusUseCase,
    required this.getMutualGroupsCountUseCase,
    required this.getMutualFriendsCountUseCase,
    required this.getFriendRequestStatusUseCase,
    required this.sendFriendRequestUseCase,
    required this.cancelFriendRequestUseCase,
    required this.acceptFriendRequestUseCase,
    required this.rejectFriendRequestUseCase,
    required this.unfriendUseCase,
    required this.blockUserUseCase,
    required this.unblockUserUseCase,
    required this.getBlockedUsersUseCase,
    required this.mediaRepository,
    required this.getOrCreateDirectChatUseCase,
  }) : super(ProfileInitial()) {
    on<LoadProfileEvent>(_onLoadProfile);
    on<UpdateProfileRequested>(_onUpdateProfile);
    on<UpdatePhotoRequested>(_onUpdatePhoto);
    on<RetryPhotoUploadRequested>(_onRetryPhotoUpload);
    on<CancelPhotoUploadRequested>(_onCancelPhotoUpload);
    on<RemovePhotoRequested>(_onRemovePhoto);
    on<SendFriendRequestRequested>(_onSendFriendRequest);
    on<CancelFriendRequestRequested>(_onCancelFriendRequest);
    on<AcceptFriendRequestRequested>(_onAcceptFriendRequest);
    on<RejectFriendRequestRequested>(_onRejectFriendRequest);
    on<UnfriendRequested>(_onUnfriend);
    on<BlockUserRequested>(_onBlockUser);
    on<UnblockUserRequested>(_onUnblockUser);
    on<UpdateSettingsRequested>(_onUpdateSettings);
    on<LoadBlockedUsersRequested>(_onLoadBlockedUsers);
    on<UnblockUserFromSettingsRequested>(_onUnblockUserFromSettings);
    on<_ProfileSnapshotReceived>(_onProfileSnapshotReceived);
    on<_ProfileStreamErrored>(_onProfileStreamErrored);
    on<_ProfileLoadTimedOut>(_onProfileLoadTimedOut);
  }

  Future<void> _onLoadProfile(LoadProfileEvent event, Emitter<ProfileState> emit) async {
    // FIX 3 (Friend Profile local-cache-first): if this *other* user's
    // profile is already cached on disk (same FriendProfileCacheService
    // ChatAppBar already uses), paint instantly from it instead of a blank
    // ProfileLoading() spinner while waiting on the network. Presence is
    // forced to isOnline:false here — same rule as FIX 1, never show a
    // stale cached online status — the live stream below still starts
    // immediately underneath and corrects it as soon as its first real
    // snapshot arrives.
    final bool isOwnProfile = event.uid == event.viewerUid;
    final cachedProfile = isOwnProfile ? null : FriendProfileCacheService.instance.getCachedSync(event.uid);

    if (cachedProfile != null) {
      emit(ProfileLoadedState(
        profile: cachedProfile.copyWith(isOnline: false),
        visibility: _currentVisibility,
      ));
    } else {
      emit(ProfileLoading());
    }

    final visibilityResult = await getRelationshipStatusUseCase(viewerUid: event.viewerUid, profileUid: event.uid);
    visibilityResult.fold(
      (_) => _currentVisibility = ProfileVisibility.nonFriend,
      (visibility) => _currentVisibility = visibility,
    );
    final afterVisibility = state;
    if (cachedProfile != null && afterVisibility is ProfileLoadedState && !emit.isDone) {
      emit(afterVisibility.copyWith(visibility: _currentVisibility));
    }

    // FIX 2 (My Profile open must never perform a hidden Firestore write):
    // see _ensuredExistsUids doc comment above — runs at most once per uid
    // per app session, not on every repeat My Profile open.
    if (isOwnProfile && !_ensuredExistsUids.contains(event.uid)) {
      await ensureProfileExistsUseCase(uid: event.uid, username: event.uid, displayName: event.uid);
      _ensuredExistsUids.add(event.uid);
    }

    _viewerUid = event.viewerUid;
    _profileUid = event.uid;
    _extraDetailsLoadedFor = null;
    _firstSnapshotReceived = false;

    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(_kLoadTimeout, () {
      if (!_firstSnapshotReceived && !isClosed) add(_ProfileLoadTimedOut());
    });

    await _profileSubscription?.cancel();
    _profileSubscription = streamProfileUseCase(event.uid).listen(
      (profile) {
        _firstSnapshotReceived = true;
        _loadTimeoutTimer?.cancel();
        _currentProfile = profile;
        if (isOwnProfile) {
          AppThemeController.instance.setThemeMode(_mapThemeMode(profile.themeMode));
        } else {
          // FIX 3: keep the on-disk cache in sync, but only actually write
          // when something changed (saveIfChanged no-ops otherwise) — the
          // "only when it actually changes" half of the requirement.
          FriendProfileCacheService.instance.saveIfChanged(profile);
        }
        if (!isClosed) add(_ProfileSnapshotReceived(profile));
      },
      onError: (Object error, StackTrace stackTrace) {
        _firstSnapshotReceived = true;
        _loadTimeoutTimer?.cancel();
        if (!isClosed) add(_ProfileStreamErrored(friendlyErrorMessage(error)));
      },
    );
  }

  void _onProfileLoadTimedOut(_ProfileLoadTimedOut event, Emitter<ProfileState> emit) {
    if (!_firstSnapshotReceived) {
      emit(ProfileErrorState(message: 'Loading is taking longer than expected. Please try again.'));
    }
  }

  void _onProfileStreamErrored(_ProfileStreamErrored event, Emitter<ProfileState> emit) {
    emit(ProfileErrorState(message: event.message));
  }

  Future<void> _onProfileSnapshotReceived(_ProfileSnapshotReceived event, Emitter<ProfileState> emit) async {
    // ROOT CAUSE FIX (friend accept/profile-refresh bug): this handler fires
    // on every new snapshot of the *profile* document (users/{uid}) — not
    // just the first one. acceptFriendRequest/blockUser/unfriend etc. all
    // write to that same user doc (e.g. friendsCount increment), which makes
    // this handler re-fire moments after Accept succeeds. It was previously
    // rebuilding ProfileLoadedState from scratch using the `_currentVisibility`
    // field, which is only ever set once in _onLoadProfile and is never
    // updated by _onAcceptFriendRequest/_onRejectFriendRequest/_onUnfriend/
    // _onBlockUser/_onUnblockUser (those only copyWith the *emitted* state).
    // So the very next profile snapshot silently reverted visibility/
    // friendRequestStatus back to the stale pre-action value, making the
    // friend profile behave like a non-friend until a manual reload. Fix:
    // carry forward the already-known visibility/friendRequestStatus/mutual
    // counts from the current state (when present) instead of resetting them.
    final previous = state;
    final visibility = previous is ProfileLoadedState ? previous.visibility : _currentVisibility;
    final friendRequestStatus =
        previous is ProfileLoadedState ? previous.friendRequestStatus : FriendRequestStatus.notFriends;
    final mutualGroupsCount = previous is ProfileLoadedState ? previous.mutualGroupsCount : null;
    final mutualFriendsCount = previous is ProfileLoadedState ? previous.mutualFriendsCount : null;

    emit(ProfileLoadedState(
      profile: event.profile,
      visibility: visibility,
      friendRequestStatus: friendRequestStatus,
      mutualGroupsCount: mutualGroupsCount,
      mutualFriendsCount: mutualFriendsCount,
    ));

    final viewerUid = _viewerUid;
    final profileUid = _profileUid;
    if (viewerUid == null || profileUid == null) return;
    if (viewerUid == profileUid || visibility == ProfileVisibility.blocked) return;
    if (_extraDetailsLoadedFor == profileUid) return;
    _extraDetailsLoadedFor = profileUid;

    final mutualResult = await getMutualGroupsCountUseCase(uid: viewerUid, otherUid: profileUid);
    final afterMutual = state;
    if (afterMutual is ProfileLoadedState && !emit.isDone) {
      mutualResult.fold(
        (_) {},
        (count) => emit(afterMutual.copyWith(mutualGroupsCount: count)),
      );
    }

    final mutualFriendsResult = await getMutualFriendsCountUseCase(uid: viewerUid, otherUid: profileUid);
    final afterMutualFriends = state;
    if (afterMutualFriends is ProfileLoadedState && !emit.isDone) {
      mutualFriendsResult.fold(
        (_) {},
        (count) => emit(afterMutualFriends.copyWith(mutualFriendsCount: count)),
      );
    }

    final friendStatusResult = await getFriendRequestStatusUseCase(viewerUid: viewerUid, profileUid: profileUid);
    final afterFriendStatus = state;
    if (afterFriendStatus is ProfileLoadedState && !emit.isDone) {
      friendStatusResult.fold(
        (_) {},
        (status) => emit(afterFriendStatus.copyWith(friendRequestStatus: status)),
      );
    }
  }

  Future<void> _onSendFriendRequest(SendFriendRequestRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await sendFriendRequestUseCase(fromUid: event.fromUid, toUid: event.toUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(friendRequestStatus: FriendRequestStatus.requestSent, isFriendActionPending: false)),
    );
  }

  Future<void> _onCancelFriendRequest(CancelFriendRequestRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await cancelFriendRequestUseCase(uid: event.uid, targetUid: event.targetUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(friendRequestStatus: FriendRequestStatus.notFriends, isFriendActionPending: false)),
    );
  }

  Future<void> _onAcceptFriendRequest(AcceptFriendRequestRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await acceptFriendRequestUseCase(uid: event.uid, requesterUid: event.requesterUid);

    // ROOT CAUSE FIX (Friend → Chat lifecycle): FriendRepositoryImpl.
    // acceptFriendRequest only ever wrote the `friends/{uid}` mirror docs —
    // nothing in the friend-request flow ever created the underlying
    // `chats/{chatId}` document, so ChatListRepositoryImpl's
    // `participantIds arrayContains` query had nothing to return for a
    // freshly-accepted friend and neither side ever saw the conversation on
    // Home. Fire this right after a successful accept, using the same
    // idempotent use case the Message button already relies on — no new
    // chat-creation logic, just triggered one step earlier in the lifecycle.
    // Runs for both uid and requesterUid symmetrically because
    // ensureDirectChatExists takes both participant ids in one call and
    // Firestore then pushes the new `participantIds` doc to *both* users'
    // already-listening Home streams in real time — no extra plumbing on
    // the requester's side needed.
    if (result.isRight()) {
      try {
        await getOrCreateDirectChatUseCase(uidA: event.uid, uidB: event.requesterUid);
      } catch (_) {
        // The friendship itself already succeeded and is the source of
        // truth; if chat creation transiently fails here it will silently
        // retry the next time either side hits Message (GetOrCreateDirectChatUseCase
        // is idempotent), so we deliberately don't fail the Accept action over it.
      }
    }

    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(
        visibility: ProfileVisibility.friend,
        friendRequestStatus: FriendRequestStatus.friends,
        isFriendActionPending: false,
      )),
    );
  }

  Future<void> _onRejectFriendRequest(RejectFriendRequestRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await rejectFriendRequestUseCase(uid: event.uid, requesterUid: event.requesterUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(friendRequestStatus: FriendRequestStatus.notFriends, isFriendActionPending: false)),
    );
  }

  Future<void> _onUnfriend(UnfriendRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await unfriendUseCase(uid: event.uid, targetUid: event.targetUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(
        visibility: ProfileVisibility.nonFriend,
        friendRequestStatus: FriendRequestStatus.notFriends,
        isFriendActionPending: false,
      )),
    );
  }

  Future<void> _onBlockUser(BlockUserRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await blockUserUseCase(uid: event.uid, targetUid: event.targetUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(
        visibility: ProfileVisibility.blocked,
        friendRequestStatus: FriendRequestStatus.notFriends,
        isFriendActionPending: false,
      )),
    );
  }

  Future<void> _onUnblockUser(UnblockUserRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await unblockUserUseCase(uid: event.uid, targetUid: event.targetUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) => emit(latest.copyWith(
        visibility: ProfileVisibility.nonFriend,
        friendRequestStatus: FriendRequestStatus.notFriends,
        isFriendActionPending: false,
      )),
    );
  }

  Future<void> _onUpdateSettings(UpdateSettingsRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;

    emit(current.copyWith(isSaving: true));
    try {
      await updateProfileUseCase(
        uid: event.uid,
        notificationsEnabled: event.notificationsEnabled,
        profilePrivacy: event.profilePrivacy,
        lastSeenVisibility: event.lastSeenVisibility,
        onlineStatusVisibility: event.onlineStatusVisibility,
        friendRequestPrivacy: event.friendRequestPrivacy,
        themeMode: event.themeMode,
        enterToSend: event.enterToSend,
        readReceiptsEnabled: event.readReceiptsEnabled,
        typingIndicatorEnabled: event.typingIndicatorEnabled,
        autoDownloadImages: event.autoDownloadImages,
        autoDownloadVideos: event.autoDownloadVideos,
        autoDownloadFiles: event.autoDownloadFiles,
        mediaWifiOnly: event.mediaWifiOnly,
      ).timeout(_kActionTimeout);
      final refreshed = state;
      if (refreshed is ProfileLoadedState && !emit.isDone) {
        emit(refreshed.copyWith(isSaving: false));
      }
    } catch (error) {
      emit(ProfileErrorState(message: friendlyErrorMessage(error)));
      emit(current.copyWith(isSaving: false));
    }
  }

  Future<void> _onLoadBlockedUsers(LoadBlockedUsersRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    final result = await getBlockedUsersUseCase(event.uid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(ProfileErrorState(message: friendlyErrorMessage(failure))),
      (blockedIds) => emit(latest.copyWith(blockedUserIds: blockedIds)),
    );
  }

  Future<void> _onUnblockUserFromSettings(UnblockUserFromSettingsRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    emit(current.copyWith(isFriendActionPending: true));
    final result = await unblockUserUseCase(uid: event.uid, targetUid: event.targetUid);
    final latest = state;
    if (latest is! ProfileLoadedState || emit.isDone) return;
    result.fold(
      (failure) => emit(latest.copyWith(isFriendActionPending: false)),
      (_) {
        final updatedBlockedIds = (latest.blockedUserIds ?? const <String>[])
            .where((id) => id != event.targetUid)
            .toList();
        emit(latest.copyWith(isFriendActionPending: false, blockedUserIds: updatedBlockedIds));
      },
    );
  }

  Future<void> _onUpdateProfile(UpdateProfileRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;

    emit(current.copyWith(isSaving: true));
    try {
      await updateProfileUseCase(
        uid: event.uid,
        displayName: event.displayName,
        username: event.username,
        bio: event.bio,
        location: event.location,
        gender: event.gender,
        birthday: event.birthday,
        phone: event.phone,
        email: event.email,
        website: event.website,
      ).timeout(_kActionTimeout);
      final refreshed = state;
      if (refreshed is ProfileLoadedState && !emit.isDone) {
        emit(refreshed.copyWith(isSaving: false));
      }
    } catch (error) {
      emit(ProfileErrorState(message: friendlyErrorMessage(error)));
      emit(current.copyWith(isSaving: false));
    }
  }

  Future<void> _onUpdatePhoto(UpdatePhotoRequested event, Emitter<ProfileState> emit) async {
    await _runPhotoUpload(uid: event.uid, slot: event.slot, file: event.file, emit: emit);
  }

  Future<void> _onRetryPhotoUpload(RetryPhotoUploadRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;
    final status = event.slot == PhotoSlot.avatar ? current.avatarUpload : current.coverUpload;
    final file = status.pendingFile;
    if (file == null) return;
    await _runPhotoUpload(uid: event.uid, slot: event.slot, file: file, emit: emit);
  }

  Future<void> _runPhotoUpload({
    required String uid,
    required PhotoSlot slot,
    required File file,
    required Emitter<ProfileState> emit,
  }) async {
    final current = state;
    if (current is! ProfileLoadedState) return;

    final int myToken = slot == PhotoSlot.avatar ? (++_avatarUploadToken) : (++_coverUploadToken);
    final uploadingStatus = PhotoUploadStatus(stage: PhotoUploadStage.uploading, progress: 0.3, pendingFile: file);
    emit(_applyUploadStatus(current, slot, uploadingStatus));

    try {
      final uploadResult = slot == PhotoSlot.avatar
          ? await uploadProfilePhotoUseCase(file: file).timeout(_kActionTimeout)
          : await uploadCoverPhotoUseCase(file: file).timeout(_kActionTimeout);

      final bool isCancelled = slot == PhotoSlot.avatar ? myToken != _avatarUploadToken : myToken != _coverUploadToken;
      if (isCancelled) {
        try {
          await mediaRepository.deleteImage(publicId: uploadResult.publicId);
        } catch (_) {}
        return;
      }

      final latest = state;
      if (latest is ProfileLoadedState && !emit.isDone) {
        emit(_applyUploadStatus(
          latest,
          slot,
          PhotoUploadStatus(stage: PhotoUploadStage.uploading, progress: 0.7, pendingFile: file),
        ));
      }

      final oldPublicId = slot == PhotoSlot.avatar ? _currentProfile?.avatarPublicId : _currentProfile?.coverPublicId;

      if (slot == PhotoSlot.avatar) {
        await updateProfilePhotoUseCase(uid: uid, photoUrl: uploadResult.secureUrl, publicId: uploadResult.publicId)
            .timeout(_kActionTimeout);
      } else {
        await updateCoverPhotoUseCase(uid: uid, photoUrl: uploadResult.secureUrl, publicId: uploadResult.publicId)
            .timeout(_kActionTimeout);
      }

      if (oldPublicId != null && oldPublicId.isNotEmpty) {
        try {
          await mediaRepository.deleteImage(publicId: oldPublicId);
        } catch (_) {}
      }

      final refreshed = state;
      if (refreshed is ProfileLoadedState && !emit.isDone) {
        emit(_applyUploadStatus(refreshed, slot, const PhotoUploadStatus()));
      }
    } catch (error) {
      final bool isCancelled = slot == PhotoSlot.avatar ? myToken != _avatarUploadToken : myToken != _coverUploadToken;
      if (isCancelled) return;

      final latest = state;
      if (latest is ProfileLoadedState && !emit.isDone) {
        emit(_applyUploadStatus(
          latest,
          slot,
          PhotoUploadStatus(stage: PhotoUploadStage.failed, pendingFile: file),
        ));
      }
    }
  }

  void _onCancelPhotoUpload(CancelPhotoUploadRequested event, Emitter<ProfileState> emit) {
    if (event.slot == PhotoSlot.avatar) {
      _avatarUploadToken++;
    } else {
      _coverUploadToken++;
    }
    final current = state;
    if (current is ProfileLoadedState) {
      emit(_applyUploadStatus(current, event.slot, const PhotoUploadStatus(stage: PhotoUploadStage.cancelled)));
    }
  }

  Future<void> _onRemovePhoto(RemovePhotoRequested event, Emitter<ProfileState> emit) async {
    final current = state;
    if (current is! ProfileLoadedState) return;

    emit(_applyUploadStatus(current, event.slot, const PhotoUploadStatus(stage: PhotoUploadStage.uploading, progress: 0.5)));
    try {
      if (event.slot == PhotoSlot.avatar) {
        await deleteProfilePhotoUseCase(uid: event.uid, publicId: _currentProfile?.avatarPublicId).timeout(_kActionTimeout);
      } else {
        await deleteCoverPhotoUseCase(uid: event.uid, publicId: _currentProfile?.coverPublicId).timeout(_kActionTimeout);
      }
      final refreshed = state;
      if (refreshed is ProfileLoadedState && !emit.isDone) {
        emit(_applyUploadStatus(refreshed, event.slot, const PhotoUploadStatus()));
      }
    } catch (error) {
      final latest = state;
      if (latest is ProfileLoadedState && !emit.isDone) {
        emit(ProfileErrorState(message: friendlyErrorMessage(error)));
        emit(_applyUploadStatus(latest, event.slot, const PhotoUploadStatus()));
      }
    }
  }

  ProfileLoadedState _applyUploadStatus(ProfileLoadedState current, PhotoSlot slot, PhotoUploadStatus status) {
    return slot == PhotoSlot.avatar ? current.copyWith(avatarUpload: status) : current.copyWith(coverUpload: status);
  }

  ThemeMode _mapThemeMode(AppThemeModePref pref) {
    switch (pref) {
      case AppThemeModePref.light:
        return ThemeMode.light;
      case AppThemeModePref.dark:
        return ThemeMode.dark;
      case AppThemeModePref.system:
        return ThemeMode.system;
    }
  }

  @override
  Future<void> close() async {
    _loadTimeoutTimer?.cancel();
    await _profileSubscription?.cancel();
    return super.close();
  }
}
