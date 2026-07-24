import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import '../../features/auth/data/datasource/auth_remote_datasource.dart';
import '../../features/auth/data/repository/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/logout_usecase.dart';
import '../../features/auth/domain/usecases/register_usecase.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_ui_cubit.dart';
import '../../features/chat/data/datasources/chat_local_data_source.dart';
import '../../features/chat/data/datasources/chat_remote_data_source.dart';
import '../../features/chat/data/repositories/chat_repository_impl.dart';
import '../../features/chat/data/repositories/group_repository_impl.dart';
import '../../features/chat/data/repositories/media_repository_impl.dart';
import '../../features/chat/domain/repositories/chat_repository.dart';
import '../../features/chat/domain/repositories/group_repository.dart';
import '../../features/chat/domain/repositories/media_repository.dart';
import '../../features/chat/domain/usecases/add_member_usecase.dart';
import '../../features/chat/domain/usecases/create_group_usecase.dart';
import '../../features/chat/domain/usecases/delete_group_photo_usecase.dart';
import '../../features/chat/domain/usecases/demote_admin_usecase.dart';
import '../../features/chat/domain/usecases/get_or_create_direct_chat_usecase.dart';
import '../../features/chat/domain/usecases/leave_group_usecase.dart';
import '../../features/chat/domain/usecases/mark_group_message_as_delivered_usecase.dart';
import '../../features/chat/domain/usecases/mark_group_message_as_read_usecase.dart';
import '../../features/chat/domain/usecases/mark_message_as_delivered_usecase.dart';
import '../../features/chat/domain/usecases/mark_message_as_read_usecase.dart';
import '../../features/chat/domain/usecases/promote_admin_usecase.dart';
import '../../features/chat/domain/usecases/remove_member_usecase.dart';
import '../../features/chat/domain/usecases/reset_group_unread_count_usecase.dart';
import '../../features/chat/domain/usecases/reset_unread_count_usecase.dart';
import '../../features/chat/domain/usecases/send_group_message_usecase.dart';
import '../../features/chat/domain/usecases/send_media_message_usecase.dart';
import '../../features/chat/domain/usecases/send_message_usecase.dart';
import '../../features/chat/data/services/voice_draft_store.dart';
import '../../features/chat/data/services/voice_playback_controller_impl.dart';
import '../../features/chat/data/services/voice_recording_coordinator.dart';
import '../../features/chat/data/services/voice_recording_service_impl.dart';
import '../../features/chat/domain/services/voice_recording_service.dart';
import '../../features/chat/domain/usecases/set_group_typing_status_usecase.dart';
import '../../features/chat/domain/usecases/set_typing_status_usecase.dart';
import '../../features/chat/domain/usecases/stream_group_messages_usecase.dart';
import '../../features/chat/domain/usecases/stream_group_typing_status_usecase.dart';
import '../../features/chat/domain/usecases/stream_group_usecase.dart';
import '../../features/chat/domain/usecases/stream_messages_usecase.dart';
import '../../features/chat/domain/usecases/stream_typing_status_usecase.dart';
import '../../features/chat/domain/usecases/update_group_name_usecase.dart';
import '../../features/chat/domain/usecases/update_group_photo_usecase.dart';
import '../../features/chat/domain/usecases/upload_group_photo_usecase.dart';
import '../../features/chat/presentation/blocs/chat_bloc.dart';
import '../../features/chat/presentation/blocs/group_bloc.dart';
import '../../features/chat/presentation/blocs/group_chat_bloc.dart';
import '../../features/chat/presentation/blocs/group_info_bloc.dart';
import '../../features/custom_alert/data/datasources/alert_audio_metadata_local_data_source.dart';
import '../../features/custom_alert/data/datasources/alert_sound_remote_data_source.dart';
import '../../features/custom_alert/data/repositories/custom_alert_repository_impl.dart';
import '../../features/custom_alert/data/repositories/friend_alert_sound_repository_impl.dart';
import '../../features/custom_alert/data/services/audio_cache_manager.dart';
import '../../features/custom_alert/data/services/audio_download_manager.dart';
import '../../features/custom_alert/data/services/audio_validation_service.dart';
import '../../features/custom_alert/domain/repositories/custom_alert_repository.dart';
import '../../features/custom_alert/domain/repositories/friend_alert_sound_repository.dart';
import '../../features/custom_alert/domain/usecases/clear_alert_audio_cache_usecase.dart';
import '../../features/custom_alert/domain/usecases/create_friend_alert_sound_usecase.dart';
import '../../features/custom_alert/domain/usecases/delete_friend_alert_sound_usecase.dart';
import '../../features/custom_alert/domain/usecases/ensure_alert_audio_cached_usecase.dart';
import '../../features/custom_alert/domain/usecases/get_alert_audio_metadata_usecase.dart';
import '../../features/custom_alert/domain/usecases/get_friend_alert_sounds_usecase.dart';
import '../../features/custom_alert/domain/usecases/get_instant_alert_audio_path_usecase.dart';
import '../../features/custom_alert/domain/usecases/rename_friend_alert_sound_usecase.dart';
import '../../features/custom_alert/domain/usecases/replace_friend_alert_sound_usecase.dart';
import '../../features/custom_alert/domain/usecases/save_alert_audio_metadata_usecase.dart';
import '../../features/chat/domain/usecases/send_message_with_alert_usecase.dart';
import '../services/voice_player_service.dart';
import '../../features/home/data/datasources/chat_list_local_data_source.dart';
import '../../features/home/data/repositories/chat_list_repository_impl.dart';
import '../../features/home/domain/repositories/chat_list_repository.dart';
import '../../features/home/domain/usecases/stream_chat_list_usecase.dart';
import '../../features/home/presentation/blocs/chat_list_bloc.dart';
import '../../features/notifications/data/repositories/notification_repository_impl.dart';
import '../../features/profile/data/repositories/friend_repository_impl.dart';
import '../../features/profile/data/repositories/profile_repository_impl.dart';
import '../../features/profile/domain/repositories/friend_repository.dart';
import '../../features/profile/domain/repositories/profile_repository.dart';
import '../../features/profile/domain/usecases/accept_friend_request_usecase.dart';
import '../../features/profile/domain/usecases/block_user_usecase.dart';
import '../../features/profile/domain/usecases/cancel_friend_request_usecase.dart';
import '../../features/profile/domain/usecases/delete_cover_photo_usecase.dart';
import '../../features/profile/domain/usecases/delete_profile_photo_usecase.dart';
import '../../features/profile/domain/usecases/ensure_profile_exists_usecase.dart';
import '../../features/profile/domain/usecases/get_blocked_users_usecase.dart';
import '../../features/profile/domain/usecases/get_friend_request_status_usecase.dart';
import '../../features/profile/domain/usecases/get_mutual_friends_count_usecase.dart';
import '../../features/profile/domain/usecases/get_mutual_groups_count_usecase.dart';
import '../../features/profile/domain/usecases/get_relationship_status_usecase.dart';
import '../../features/profile/domain/usecases/reject_friend_request_usecase.dart';
import '../../features/profile/domain/usecases/send_friend_request_usecase.dart';
import '../../features/profile/domain/usecases/set_online_status_usecase.dart';
import '../../features/profile/domain/usecases/stream_profile_usecase.dart';
import '../../features/profile/domain/usecases/unblock_user_usecase.dart';
import '../../features/profile/domain/usecases/unfriend_usecase.dart';
import '../../features/profile/domain/usecases/update_cover_photo_usecase.dart';
import '../../features/profile/domain/usecases/update_profile_photo_usecase.dart';
import '../../features/profile/domain/usecases/update_profile_usecase.dart';
import '../../features/profile/domain/usecases/upload_cover_photo_usecase.dart';
import '../../features/profile/domain/usecases/upload_profile_photo_usecase.dart';
import '../../features/profile/presentation/blocs/profile_bloc.dart';
import '../../features/notifications/domain/repositories/notification_repository.dart';
import '../../features/notifications/domain/usecases/get_fcm_token_usecase.dart';
import '../../features/notifications/domain/usecases/initialize_notifications_usecase.dart';
import '../../features/notifications/domain/usecases/request_notification_permission_usecase.dart';
import '../../features/notifications/domain/usecases/stream_fcm_token_refresh_usecase.dart';
import '../services/notification_service.dart';
import '../services/fcm_token_sync_service.dart';
import '../services/voice_recorder_service.dart';
import '../../features/search/data/repositories/user_search_repository_impl.dart';
import '../../features/search/domain/repositories/user_search_repository.dart';
import '../../features/search/domain/usecases/search_users_usecase.dart';
import '../../features/search/presentation/blocs/user_search_bloc.dart';
import '../../features/admin/data/repositories/admin_repository_impl.dart';
import '../../features/admin/domain/repositories/admin_repository.dart';
import '../../features/admin/domain/usecases/ban_user_usecase.dart';
import '../../features/admin/domain/usecases/disable_account_usecase.dart';
import '../../features/admin/domain/usecases/get_admin_action_log_usecase.dart';
import '../../features/admin/domain/usecases/get_admin_dashboard_stats_usecase.dart';
import '../../features/admin/domain/usecases/get_moderation_reports_usecase.dart';
import '../../features/admin/domain/usecases/get_user_warnings_usecase.dart';
import '../../features/admin/domain/usecases/issue_warning_usecase.dart';
import '../../features/admin/domain/usecases/lookup_user_by_uid_usecase.dart';
import '../../features/admin/domain/usecases/lookup_users_by_username_usecase.dart';
import '../../features/admin/domain/usecases/report_group_usecase.dart';
import '../../features/admin/domain/usecases/report_message_usecase.dart';
import '../../features/admin/domain/usecases/report_user_usecase.dart';
import '../../features/admin/domain/usecases/restore_account_usecase.dart';
import '../../features/admin/domain/usecases/get_ban_history_usecase.dart';
import '../../features/admin/domain/usecases/unban_user_usecase.dart';
import '../../features/admin/domain/usecases/update_report_status_usecase.dart';
import '../../features/admin/presentation/cubit/admin_dashboard_cubit.dart';
import '../../features/admin/presentation/cubit/admin_user_detail_cubit.dart';
import '../../features/admin/presentation/cubit/admin_user_lookup_cubit.dart';
import '../../features/admin/presentation/cubit/moderation_queue_cubit.dart';
import '../utils/moderation_guard.dart';
import '../security/authorization/admin_authorization.dart';
import '../security/authorization/ban_authorization.dart';
import '../security/authorization/friend_action_authorization.dart';
import '../security/gateways/admin_security_gateway.dart';
import '../security/gateways/cloud_function_admin_security_gateway.dart';
import '../security/gateways/friend_security_gateway.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Cubits / Blocs
  sl.registerFactory(() => AuthCubit(loginUseCase: sl(), registerUseCase: sl()));
  sl.registerFactory(() => AuthUiCubit());
  sl.registerFactory(() => ChatBloc(
        chatRepository: sl(),
        sendMessageUseCase: sl(),
        streamMessagesUseCase: sl(),
        resetUnreadCountUseCase: sl(),
        setTypingStatusUseCase: sl(),
        streamTypingStatusUseCase: sl(),
        markMessageAsDeliveredUseCase: sl(),
        markMessageAsReadUseCase: sl(),
        mediaRepository: sl(),
        sendMediaMessageUseCase: sl(),
        sendMessageWithAlertUseCase: sl(),
      ));
  sl.registerFactory(() => ChatListBloc(
        chatListRepository: sl(),
        streamChatListUseCase: sl(),
      ));
  sl.registerFactory(() => GroupBloc(createGroupUseCase: sl()));
  sl.registerFactory(() => GroupChatBloc(
        groupRepository: sl(),
        sendGroupMessageUseCase: sl(),
        streamGroupMessagesUseCase: sl(),
        resetGroupUnreadCountUseCase: sl(),
        setGroupTypingStatusUseCase: sl(),
        streamGroupTypingStatusUseCase: sl(),
        markGroupMessageAsDeliveredUseCase: sl(),
        markGroupMessageAsReadUseCase: sl(),
      ));
  sl.registerFactory(() => GroupInfoBloc(
        streamGroupUseCase: sl(),
        addMemberUseCase: sl(),
        removeMemberUseCase: sl(),
        leaveGroupUseCase: sl(),
        promoteAdminUseCase: sl(),
        demoteAdminUseCase: sl(),
        updateGroupNameUseCase: sl(),
        uploadGroupPhotoUseCase: sl(),
        updateGroupPhotoUseCase: sl(),
        deleteGroupPhotoUseCase: sl(),
      ));
  sl.registerFactory(() => ProfileBloc(
        streamProfileUseCase: sl(),
        ensureProfileExistsUseCase: sl(),
        updateProfileUseCase: sl(),
        uploadProfilePhotoUseCase: sl(),
        updateProfilePhotoUseCase: sl(),
        deleteProfilePhotoUseCase: sl(),
        uploadCoverPhotoUseCase: sl(),
        updateCoverPhotoUseCase: sl(),
        deleteCoverPhotoUseCase: sl(),
        getRelationshipStatusUseCase: sl(),
        getMutualGroupsCountUseCase: sl(),
        getMutualFriendsCountUseCase: sl(),
        getFriendRequestStatusUseCase: sl(),
        sendFriendRequestUseCase: sl(),
        cancelFriendRequestUseCase: sl(),
        acceptFriendRequestUseCase: sl(),
        rejectFriendRequestUseCase: sl(),
        unfriendUseCase: sl(),
        blockUserUseCase: sl(),
        unblockUserUseCase: sl(),
        getBlockedUsersUseCase: sl(),
        mediaRepository: sl(),
        getOrCreateDirectChatUseCase: sl(),
      ));

  sl.registerFactory(() => UserSearchBloc(searchUsersUseCase: sl()));

  // Phase 8.6A (Admin Foundation)
  sl.registerFactory(() => AdminDashboardCubit(getAdminDashboardStatsUseCase: sl()));
  sl.registerFactory(() => AdminUserLookupCubit(lookupUserByUidUseCase: sl(), lookupUsersByUsernameUseCase: sl()));
  sl.registerFactoryParam<AdminUserDetailCubit, String, String>(
    (uid, adminUid) => AdminUserDetailCubit(
      uid: uid,
      adminUid: adminUid,
      lookupUserByUidUseCase: sl(),
      banUserUseCase: sl(),
      unbanUserUseCase: sl(),
      disableAccountUseCase: sl(),
      restoreAccountUseCase: sl(),
      getBanHistoryUseCase: sl(),
      getUserWarningsUseCase: sl(),
      issueWarningUseCase: sl(),
    ),
  );
  // Phase 8.6B (Moderation System)
  sl.registerFactory(() => ModerationQueueCubit(
        getModerationReportsUseCase: sl(),
        updateReportStatusUseCase: sl(),
      ));

  // UseCases
  sl.registerLazySingleton(() => LoginUseCase(sl(), sl()));
  sl.registerLazySingleton(() => RegisterUseCase(sl()));
  sl.registerLazySingleton(() => LogoutUseCase(sl()));
  sl.registerLazySingleton(() => SendMessageUseCase(sl(), sl()));
  sl.registerLazySingleton(() => GetOrCreateDirectChatUseCase(sl()));
  sl.registerLazySingleton(() => SendMediaMessageUseCase(sl(), sl()));
  sl.registerLazySingleton(() => StreamMessagesUseCase(sl()));
  sl.registerLazySingleton(() => StreamChatListUseCase(sl()));
  sl.registerLazySingleton(() => CreateGroupUseCase(sl(), sl()));
  sl.registerLazySingleton(() => SendGroupMessageUseCase(sl(), sl()));
  sl.registerLazySingleton(() => StreamGroupMessagesUseCase(sl()));
  sl.registerLazySingleton(() => StreamGroupUseCase(sl()));
  sl.registerLazySingleton(() => AddMemberUseCase(sl(), sl()));
  sl.registerLazySingleton(() => RemoveMemberUseCase(sl(), sl()));
  sl.registerLazySingleton(() => LeaveGroupUseCase(sl(), sl()));
  sl.registerLazySingleton(() => PromoteAdminUseCase(sl(), sl()));
  sl.registerLazySingleton(() => DemoteAdminUseCase(sl(), sl()));
  sl.registerLazySingleton(() => ResetGroupUnreadCountUseCase(sl()));
  sl.registerLazySingleton(() => ResetUnreadCountUseCase(sl()));
  sl.registerLazySingleton(() => UpdateGroupNameUseCase(sl(), sl()));
  sl.registerLazySingleton(() => UploadGroupPhotoUseCase(sl()));
  sl.registerLazySingleton(() => UpdateGroupPhotoUseCase(sl(), sl()));
  sl.registerLazySingleton(() => DeleteGroupPhotoUseCase(sl()));
  // Day 6 Milestone 1 (Typing Indicator)
  sl.registerLazySingleton(() => SetTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => StreamTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => SetGroupTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => StreamGroupTypingStatusUseCase(sl()));
  // Day 6 Milestone 2 (Delivery Status)
  sl.registerLazySingleton(() => MarkMessageAsDeliveredUseCase(sl(), sl()));
  sl.registerLazySingleton(() => MarkGroupMessageAsDeliveredUseCase(sl(), sl()));
  // Day 6 Milestone 3 (Read Receipts)
  sl.registerLazySingleton(() => MarkMessageAsReadUseCase(sl(), sl()));
  sl.registerLazySingleton(() => MarkGroupMessageAsReadUseCase(sl(), sl()));
  // Milestone 7.1 (Notification Foundation)
  sl.registerLazySingleton(() => InitializeNotificationsUseCase(sl()));
  sl.registerLazySingleton(() => RequestNotificationPermissionUseCase(sl()));
  sl.registerLazySingleton(() => GetFcmTokenUseCase(sl()));
  sl.registerLazySingleton(() => StreamFcmTokenRefreshUseCase(sl()));
  sl.registerLazySingleton(() => FcmTokenSyncService(
        getFcmTokenUseCase: sl(),
        streamFcmTokenRefreshUseCase: sl(),
        firestore: sl(),
      ));
  sl.registerLazySingleton(() => GetAlertAudioMetadataUseCase(sl()));
  sl.registerLazySingleton(() => SaveAlertAudioMetadataUseCase(sl()));
  sl.registerLazySingleton(() => EnsureAlertAudioCachedUseCase(sl()));
  sl.registerLazySingleton(() => GetInstantAlertAudioPathUseCase(sl()));
  sl.registerLazySingleton(() => ClearAlertAudioCacheUseCase(sl()));
  sl.registerLazySingleton(() => GetFriendAlertSoundsUseCase(sl()));
  sl.registerLazySingleton(() => CreateFriendAlertSoundUseCase(sl()));
  sl.registerLazySingleton(() => RenameFriendAlertSoundUseCase(sl()));
  sl.registerLazySingleton(() => ReplaceFriendAlertSoundUseCase(sl()));
  sl.registerLazySingleton(() => DeleteFriendAlertSoundUseCase(sl()));
  sl.registerLazySingleton(() => SendMessageWithAlertUseCase(sl(), sl()));
  sl.registerLazySingleton(() => StreamProfileUseCase(sl()));
  sl.registerLazySingleton(() => EnsureProfileExistsUseCase(sl()));
  sl.registerLazySingleton(() => UpdateProfileUseCase(sl(), sl()));
  sl.registerLazySingleton(() => UploadProfilePhotoUseCase(sl()));
  sl.registerLazySingleton(() => UpdateProfilePhotoUseCase(sl()));
  sl.registerLazySingleton(() => DeleteProfilePhotoUseCase(mediaRepository: sl(), profileRepository: sl()));
  sl.registerLazySingleton(() => UploadCoverPhotoUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCoverPhotoUseCase(sl()));
  sl.registerLazySingleton(() => DeleteCoverPhotoUseCase(mediaRepository: sl(), profileRepository: sl()));
  sl.registerLazySingleton(() => GetRelationshipStatusUseCase(sl()));
  sl.registerLazySingleton(() => GetMutualGroupsCountUseCase(sl()));
  sl.registerLazySingleton(() => GetMutualFriendsCountUseCase(sl()));
  sl.registerLazySingleton(() => GetFriendRequestStatusUseCase(sl()));
  sl.registerLazySingleton(() => SendFriendRequestUseCase(sl(), sl()));
  sl.registerLazySingleton(() => CancelFriendRequestUseCase(sl()));
  sl.registerLazySingleton(() => AcceptFriendRequestUseCase(sl()));
  sl.registerLazySingleton(() => RejectFriendRequestUseCase(sl()));
  sl.registerLazySingleton(() => UnfriendUseCase(sl()));
  sl.registerLazySingleton(() => BlockUserUseCase(sl()));
  sl.registerLazySingleton(() => UnblockUserUseCase(sl()));
  sl.registerLazySingleton(() => GetBlockedUsersUseCase(sl()));
  sl.registerLazySingleton(() => SetOnlineStatusUseCase(sl()));
  sl.registerLazySingleton(() => SearchUsersUseCase(sl()));

  // Phase 8.6A (Admin Foundation)
  sl.registerLazySingleton(() => GetAdminDashboardStatsUseCase(sl()));
  sl.registerLazySingleton(() => LookupUserByUidUseCase(sl()));
  sl.registerLazySingleton(() => LookupUsersByUsernameUseCase(sl()));
  sl.registerLazySingleton(() => BanUserUseCase(sl()));
  sl.registerLazySingleton(() => UnbanUserUseCase(sl()));
  sl.registerLazySingleton(() => DisableAccountUseCase(sl()));
  sl.registerLazySingleton(() => RestoreAccountUseCase(sl()));
  sl.registerLazySingleton(() => GetBanHistoryUseCase(sl()));

  // Phase 8.6B (Moderation System)
  sl.registerLazySingleton(() => ReportUserUseCase(sl()));
  sl.registerLazySingleton(() => ReportMessageUseCase(sl()));
  sl.registerLazySingleton(() => ReportGroupUseCase(sl()));
  sl.registerLazySingleton(() => GetModerationReportsUseCase(sl()));
  sl.registerLazySingleton(() => UpdateReportStatusUseCase(sl<AdminSecurityGateway>()));
  sl.registerLazySingleton(() => IssueWarningUseCase(sl<AdminSecurityGateway>()));
  sl.registerLazySingleton(() => GetUserWarningsUseCase(sl()));
  sl.registerLazySingleton(() => GetAdminActionLogUseCase(sl()));

  // Repositories
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(remoteDataSource: sl()));
  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(remoteDataSource: sl(), localDataSource: sl(), firestore: sl()),
  );
  sl.registerLazySingleton<GroupRepository>(() => GroupRepositoryImpl(firestore: sl(), localDataSource: sl()));
  sl.registerLazySingleton<MediaRepository>(() => MediaRepositoryImpl(client: sl()));
  sl.registerLazySingleton<ChatListRepository>(
    () => ChatListRepositoryImpl(localDataSource: sl(), firestore: sl()),
  );
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(notificationService: sl()),
  );
  sl.registerLazySingleton<ProfileRepository>(() => ProfileRepositoryImpl(firestore: sl()));
  sl.registerLazySingleton<FriendRepository>(() => FriendRepositoryImpl(firestore: sl()));
  sl.registerLazySingleton<UserSearchRepository>(() => UserSearchRepositoryImpl(firestore: sl(), friendRepository: sl()));
  sl.registerLazySingleton<AdminRepository>(() => AdminRepositoryImpl(firestore: sl(), profileRepository: sl()));

  // Phase 9.0D (Security Gateway Integration)
  sl.registerLazySingleton<AdminAuthorization>(() => const LocalAdminAuthorization());
  sl.registerLazySingleton<BanAuthorization>(() => LocalBanAuthorization(adminAuthorization: sl()));
  sl.registerLazySingleton<FriendActionAuthorization>(() => const LocalFriendActionAuthorization());
  sl.registerLazySingleton<FriendSecurityGateway>(
    () => LocalFriendSecurityGateway(friendRepository: sl(), friendActionAuthorization: sl()),
  );
  sl.registerLazySingleton<AdminSecurityGateway>(
    () => CloudFunctionAdminSecurityGateway(functions: sl()),
  );
  sl.registerLazySingleton<CustomAlertRepository>(
    () => CustomAlertRepositoryImpl(
      metadataLocalDataSource: sl(),
      cacheManager: sl(),
      downloadManager: sl(),
      validationService: sl(),
    ),
  );
  sl.registerLazySingleton<FriendAlertSoundRepository>(
    () => FriendAlertSoundRepositoryImpl(
      remoteDataSource: sl(),
      mediaRepository: sl(),
      customAlertRepository: sl(),
    ),
  );

  // DataSources
  sl.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSourceImpl(firestore: sl()));
  sl.registerLazySingleton<ChatRemoteDataSource>(() => ChatRemoteDataSourceImpl(firestore: sl()));
  sl.registerLazySingleton<ChatLocalDataSource>(() => ChatLocalDataSourceImpl());
  sl.registerLazySingleton<ChatListLocalDataSource>(() => ChatListLocalDataSourceImpl());
  sl.registerLazySingleton<AlertAudioMetadataLocalDataSource>(() => AlertAudioMetadataLocalDataSourceImpl());
  sl.registerLazySingleton<AlertSoundRemoteDataSource>(() => AlertSoundRemoteDataSourceImpl(firestore: sl()));

  sl.registerLazySingleton<AudioCacheManager>(() => AudioCacheManager.instance);
  sl.registerLazySingleton<AudioDownloadManager>(() => AudioDownloadManager(client: sl()));
  sl.registerLazySingleton<AudioValidationService>(() => const AudioValidationService());

  // External
  sl.registerLazySingleton<FirebaseFirestore>(() => FirebaseFirestore.instance);
  sl.registerLazySingleton<FirebaseFunctions>(() => FirebaseFunctions.instance);

  // Phase 8.6C (Ban System)
  sl.registerLazySingleton(() => ModerationGuard(sl()));
  sl.registerLazySingleton<http.Client>(() => http.Client()); // Milestone 6: Cloudinary HTTP calls
  sl.registerLazySingleton<NotificationService>(() => NotificationService.instance); // Milestone 7.1

  // Phase 8.3 (Real Voice System)
  sl.registerLazySingleton<VoiceRecordingService>(() => VoiceRecordingServiceImpl(VoiceRecorderService.instance));
  sl.registerFactory<VoicePlayerService>(() => VoicePlayerService());
  sl.registerFactory<VoicePlaybackController>(() => VoicePlaybackControllerImpl(VoicePlayerService()));

  // Voice Message audit (WhatsApp-style recording UX, Bugs 1-4): draft
  // store + coordinator are singletons so a recording — and its "paused as
  // a draft" state — survives ChatScreen being torn down and recreated
  // (backgrounding, navigating to another in-app page, etc.), same as the
  // VoiceRecordingService singleton it wraps. No new Firestore/repository
  // dependency — draftStore is purely local.
  sl.registerLazySingleton<VoiceDraftStore>(() => VoiceDraftStore.instance);
  sl.registerLazySingleton<VoiceRecordingCoordinator>(
    () => VoiceRecordingCoordinator(sl<VoiceRecordingService>(), sl<VoiceDraftStore>()),
  );
}
