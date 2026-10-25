import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/push_notification_sender_service.dart';
import '../services/group_profile_bulk_warmup_service.dart';
import '../services/profile_bulk_warmup_service.dart';
import '../services/shared_presence_manager.dart';
import '../../features/auth/data/datasource/auth_remote_datasource.dart';
import '../../features/auth/data/repository/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/logout_usecase.dart';
import '../../features/auth/domain/usecases/register_usecase.dart';
import '../../features/auth/domain/usecases/forgot_password_usecase.dart';
import '../../features/auth/domain/usecases/resend_email_verification_usecase.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_ui_cubit.dart';
import '../../features/chat/data/datasources/chat_local_data_source.dart';
import '../../features/chat/data/datasources/message_inbox_applicator.dart';
import '../../features/chat/data/datasources/group_delta_remote_data_source.dart';
import '../../features/chat/data/datasources/group_info_local_data_source.dart';
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
import '../../features/chat/domain/usecases/get_cached_messages_usecase.dart';
import '../../features/chat/domain/usecases/stream_typing_status_usecase.dart';
import '../../features/chat/domain/usecases/update_group_name_usecase.dart';
import '../../features/chat/domain/usecases/update_group_photo_usecase.dart';
import '../../features/chat/domain/usecases/upload_group_photo_usecase.dart';
import '../../features/chat/domain/usecases/watch_group_member_presence_usecase.dart';
import '../../features/chat/presentation/blocs/chat_bloc.dart';
import '../../features/chat/presentation/blocs/group_bloc.dart';
import '../../features/chat/presentation/blocs/group_chat_bloc.dart';
import '../../features/chat/presentation/blocs/group_info_bloc.dart';
import '../../features/custom_alert/data/datasources/alert_audio_metadata_local_data_source.dart';
import '../../features/custom_alert/data/datasources/alert_sound_local_data_source.dart';
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
import '../services/alert_autoplay_service.dart';
import '../services/alert_download_pipeline.dart';
import '../services/alert_foreground_service_bridge.dart';
import '../../features/custom_alert/domain/usecases/get_alert_audio_metadata_usecase.dart';
import '../../features/custom_alert/domain/usecases/get_friend_alert_sounds_usecase.dart';
import '../../features/custom_alert/domain/usecases/get_instant_alert_audio_path_usecase.dart';
import '../../features/custom_alert/domain/usecases/rename_friend_alert_sound_usecase.dart';
import '../../features/custom_alert/domain/usecases/replace_friend_alert_sound_usecase.dart';
import '../../features/custom_alert/domain/usecases/save_alert_audio_metadata_usecase.dart';
import '../../features/chat/domain/usecases/send_message_with_alert_usecase.dart';
import '../services/voice_player_service.dart';
import '../../features/home/data/datasources/chat_list_local_data_source.dart';
import '../../features/home/data/datasources/chat_list_remote_data_source.dart';
import '../../features/home/data/repositories/chat_list_repository_impl.dart';
import '../../features/home/domain/repositories/chat_list_repository.dart';
import '../../features/home/domain/usecases/stream_chat_list_usecase.dart';
import '../../features/home/domain/usecases/get_cached_chat_list_usecase.dart';
import '../../features/home/presentation/blocs/chat_list_bloc.dart';
import '../../features/notifications/data/repositories/notification_repository_impl.dart';
import '../../features/notifications/data/repositories/notification_inbox_repository_impl.dart';
import '../../features/notifications/data/datasources/notification_remote_data_source.dart';
import '../../features/notifications/data/datasources/notification_local_data_source.dart';
import '../../features/profile/data/datasources/profile_local_data_source.dart';
import '../../features/profile/data/datasources/profile_remote_data_source.dart';
import '../../features/profile/data/repositories/friend_repository_impl.dart';
import '../../features/profile/data/datasources/friend_local_data_source.dart';
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
import '../../features/profile/domain/usecases/heartbeat_presence_usecase.dart';
import '../services/presence_activity_pinger.dart';
import '../../features/profile/domain/usecases/stream_profile_usecase.dart';
import '../../features/profile/domain/usecases/unblock_user_usecase.dart';
import '../../features/profile/domain/usecases/unfriend_usecase.dart';
import '../../features/profile/domain/usecases/get_friends_usecase.dart';
import '../../features/profile/domain/usecases/stream_friends_usecase.dart';
import '../../features/profile/domain/usecases/update_cover_photo_usecase.dart';
import '../../features/profile/domain/usecases/update_profile_photo_usecase.dart';
import '../../features/profile/domain/usecases/update_profile_usecase.dart';
import '../../features/profile/domain/usecases/upload_cover_photo_usecase.dart';
import '../../features/profile/domain/usecases/upload_profile_photo_usecase.dart';
import '../../features/profile/presentation/blocs/profile_bloc.dart';
import '../../features/notifications/domain/repositories/notification_repository.dart';
import '../../features/notifications/domain/repositories/notification_inbox_repository.dart';
import '../../features/notifications/domain/usecases/get_fcm_token_usecase.dart';
import '../../features/notifications/domain/usecases/initialize_notifications_usecase.dart';
import '../../features/notifications/domain/usecases/request_notification_permission_usecase.dart';
import '../../features/notifications/domain/usecases/stream_fcm_token_refresh_usecase.dart';
import '../../features/notifications/domain/usecases/stream_notifications_usecase.dart';
import '../../features/notifications/domain/usecases/stream_unread_notification_count_usecase.dart';
import '../../features/notifications/domain/usecases/mark_notification_read_usecase.dart';
import '../../features/notifications/domain/usecases/mark_all_notifications_read_usecase.dart';
import '../../features/notifications/domain/usecases/delete_notification_usecase.dart';
import '../../features/notifications/presentation/blocs/notification_bloc.dart';
import '../../features/notifications/presentation/blocs/notification_badge_cubit.dart';
import '../services/notification_service.dart';
import '../services/fcm_token_sync_service.dart';
import '../services/voice_recorder_service.dart';
import '../../features/search/data/datasources/user_search_local_data_source.dart';
import '../../features/search/data/datasources/user_search_remote_data_source.dart';
import '../../features/search/data/repositories/user_search_repository_impl.dart';
import '../../features/search/domain/repositories/user_search_repository.dart';
import '../../features/search/domain/usecases/search_users_usecase.dart';
import '../../features/search/presentation/blocs/user_search_bloc.dart';
import '../../features/admin/data/datasources/admin_local_data_source.dart';
import '../../features/admin/data/datasources/admin_remote_data_source.dart';
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
import '../../features/admin/domain/usecases/watch_admin_activity_usecase.dart';
import '../../features/admin/presentation/cubit/admin_dashboard_cubit.dart';
import '../../features/admin/presentation/cubit/admin_user_detail_cubit.dart';
import '../../features/admin/presentation/cubit/admin_user_lookup_cubit.dart';
import '../../features/admin/presentation/cubit/moderation_queue_cubit.dart';
import '../utils/moderation_guard.dart';
import '../security/authorization/admin_authorization.dart';
import '../security/authorization/ban_authorization.dart';
import '../security/authorization/friend_action_authorization.dart';
import '../security/gateways/admin_security_gateway.dart';
import '../security/gateways/friend_security_gateway.dart';

// Call module — Milestone 2 (Data Layer). Foundation Layer usecase
// registration lives in registerCallFoundationUsecases (features/call/di/
// call_injection.dart, from the prior milestone, unmodified); only the
// concrete datasource/repository bindings are new here.
import '../../features/call/data/datasources/agora_datasource.dart';
import '../../features/call/data/datasources/agora_datasource_impl.dart';
import '../../features/call/data/datasources/call_realtime_datasource.dart';
import '../../features/call/data/datasources/call_realtime_datasource_impl.dart';
import '../../features/call/data/datasources/call_remote_datasource.dart';
import '../../features/call/data/datasources/call_remote_datasource_impl.dart';
import '../../features/call/data/repositories/agora_repository_impl.dart';
import '../../features/call/data/repositories/call_repository_impl.dart';
import '../../features/call/di/call_injection.dart';
import '../../features/call/di/call_presentation_injection.dart';
import '../../features/call/domain/repositories/agora_repository.dart';
import '../../features/call/domain/repositories/call_repository.dart';

final sl = GetIt.instance;

Future<void> init() async {
  sl.registerFactory(() => AuthCubit(loginUseCase: sl(), registerUseCase: sl()));
  sl.registerFactory(() => AuthUiCubit());
  sl.registerFactory(() => ChatBloc(
        chatRepository: sl(),
        sendMessageUseCase: sl(),
        streamMessagesUseCase: sl(),
        getCachedMessagesUseCase: sl(),
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
        getCachedChatListUseCase: sl(),
        profileBulkWarmupService: sl(),
      ));
  sl.registerFactory(() => NotificationBloc(
        streamNotificationsUseCase: sl(),
        markNotificationReadUseCase: sl(),
        markAllNotificationsReadUseCase: sl(),
        deleteNotificationUseCase: sl(),
      ));
  sl.registerLazySingleton(() => NotificationBadgeCubit(streamUnreadNotificationCountUseCase: sl()));
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

  sl.registerFactory(() => AdminDashboardCubit(
        getAdminDashboardStatsUseCase: sl(),
        watchAdminActivityUseCase: sl(),
      ));
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
  sl.registerFactory(() => ModerationQueueCubit(
        getModerationReportsUseCase: sl(),
        updateReportStatusUseCase: sl(),
        watchAdminActivityUseCase: sl(),
      ));

  sl.registerLazySingleton(() => LoginUseCase(sl(), sl()));
  sl.registerLazySingleton(() => RegisterUseCase(sl()));
  sl.registerLazySingleton(() => LogoutUseCase(sl()));
  sl.registerLazySingleton(() => ForgotPasswordUseCase(sl()));
  sl.registerLazySingleton(() => ResendEmailVerificationUseCase(sl()));
  sl.registerLazySingleton(() => SendMessageUseCase(sl(), sl()));
  sl.registerLazySingleton(() => GetOrCreateDirectChatUseCase(sl()));
  sl.registerLazySingleton(() => SendMediaMessageUseCase(sl(), sl()));
  sl.registerLazySingleton(() => StreamMessagesUseCase(sl()));
  sl.registerLazySingleton(() => GetCachedMessagesUseCase(sl()));
  sl.registerLazySingleton(() => StreamChatListUseCase(sl()));
  sl.registerLazySingleton(() => GetCachedChatListUseCase(sl()));
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
  sl.registerLazySingleton(() => WatchGroupMemberPresenceUseCase(sl()));
  sl.registerLazySingleton(() => SetTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => StreamTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => SetGroupTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => StreamGroupTypingStatusUseCase(sl()));
  sl.registerLazySingleton(() => MarkMessageAsDeliveredUseCase(sl(), sl()));
  sl.registerLazySingleton(() => MarkGroupMessageAsDeliveredUseCase(sl(), sl()));
  sl.registerLazySingleton(() => MarkMessageAsReadUseCase(sl(), sl()));
  sl.registerLazySingleton(() => MarkGroupMessageAsReadUseCase(sl(), sl()));
  sl.registerLazySingleton(() => InitializeNotificationsUseCase(sl()));
  sl.registerLazySingleton(() => RequestNotificationPermissionUseCase(sl()));
  sl.registerLazySingleton(() => GetFcmTokenUseCase(sl()));
  sl.registerLazySingleton(() => StreamFcmTokenRefreshUseCase(sl()));
  sl.registerLazySingleton(() => StreamNotificationsUseCase(sl()));
  sl.registerLazySingleton(() => StreamUnreadNotificationCountUseCase(sl()));
  sl.registerLazySingleton(() => MarkNotificationReadUseCase(sl()));
  sl.registerLazySingleton(() => MarkAllNotificationsReadUseCase(sl()));
  sl.registerLazySingleton(() => DeleteNotificationUseCase(sl()));
  sl.registerLazySingleton(() => FcmTokenSyncService(
        getFcmTokenUseCase: sl(),
        streamFcmTokenRefreshUseCase: sl(),
        supabase: sl(),
      ));
  sl.registerLazySingleton(() => PushNotificationSenderService(client: sl(), supabase: sl()));
  sl.registerLazySingleton(() => GetAlertAudioMetadataUseCase(sl()));
  sl.registerLazySingleton(() => SaveAlertAudioMetadataUseCase(sl()));
  sl.registerLazySingleton(() => EnsureAlertAudioCachedUseCase(sl()));
  sl.registerLazySingleton(() => GetInstantAlertAudioPathUseCase(sl()));
  sl.registerLazySingleton<AlertForegroundServiceBridge>(() => AlertForegroundServiceBridge.instance);
  sl.registerLazySingleton<AlertAutoplayService>(() => AlertAutoplayService());
  sl.registerLazySingleton<AlertDownloadPipeline>(() => AlertDownloadPipeline(
        ensureAlertAudioCachedUseCase: sl(),
        autoplayService: sl(),
        foregroundServiceBridge: sl(),
      ));
  sl.registerLazySingleton(() => ClearAlertAudioCacheUseCase(sl()));
  sl.registerLazySingleton(() => WatchFriendAlertSoundsUseCase(sl()));
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
  sl.registerLazySingleton(() => GetFriendsUseCase(sl()));
  sl.registerLazySingleton(() => StreamFriendsUseCase(sl()));
  sl.registerLazySingleton(() => BlockUserUseCase(sl()));
  sl.registerLazySingleton(() => UnblockUserUseCase(sl()));
  sl.registerLazySingleton(() => GetBlockedUsersUseCase(sl()));
  sl.registerLazySingleton(() => SetOnlineStatusUseCase(sl()));
  sl.registerLazySingleton(() => HeartbeatPresenceUseCase(sl()));
  sl.registerLazySingleton(() => PresenceActivityPinger(sl()));
  sl.registerLazySingleton(() => SearchUsersUseCase(sl()));

  sl.registerLazySingleton(() => GetAdminDashboardStatsUseCase(sl()));
  sl.registerLazySingleton(() => LookupUserByUidUseCase(sl()));
  sl.registerLazySingleton(() => LookupUsersByUsernameUseCase(sl()));
  sl.registerLazySingleton(() => BanUserUseCase(sl()));
  sl.registerLazySingleton(() => UnbanUserUseCase(sl()));
  sl.registerLazySingleton(() => DisableAccountUseCase(sl()));
  sl.registerLazySingleton(() => RestoreAccountUseCase(sl()));
  sl.registerLazySingleton(() => GetBanHistoryUseCase(sl()));

  sl.registerLazySingleton(() => ReportUserUseCase(sl()));
  sl.registerLazySingleton(() => ReportMessageUseCase(sl()));
  sl.registerLazySingleton(() => ReportGroupUseCase(sl()));
  sl.registerLazySingleton(() => GetModerationReportsUseCase(sl()));
  sl.registerLazySingleton(() => UpdateReportStatusUseCase(sl<AdminSecurityGateway>()));
  sl.registerLazySingleton(() => IssueWarningUseCase(sl<AdminSecurityGateway>()));
  sl.registerLazySingleton(() => GetUserWarningsUseCase(sl()));
  sl.registerLazySingleton(() => GetAdminActionLogUseCase(sl()));
  sl.registerLazySingleton(() => WatchAdminActivityUseCase(sl()));

  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(remoteDataSource: sl()));
  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      supabase: sl(),
      pushNotificationSender: sl(),
      inboxApplicator: sl(),
      presenceActivityPinger: sl(),
    ),
  );
  sl.registerLazySingleton<GroupInfoLocalDataSource>(() => GroupInfoLocalDataSourceImpl());
  sl.registerLazySingleton<GroupDeltaRemoteDataSource>(() => GroupDeltaRemoteDataSource(supabase: sl()));
  sl.registerLazySingleton<GroupRepository>(
    () => GroupRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      supabase: sl(),
      presenceActivityPinger: sl(),
      groupInfoLocalDataSource: sl(),
      groupDeltaRemoteDataSource: sl(),
    ),
  );
  sl.registerLazySingleton<MediaRepository>(() => MediaRepositoryImpl(client: sl()));
  sl.registerLazySingleton<ChatListRepository>(
    () => ChatListRepositoryImpl(
      localDataSource: sl(),
      remoteDataSource: sl(),
      firestore: sl(),
      supabase: sl(),
      friendLocalDataSource: sl(),
    ),
  );
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(notificationService: sl()),
  );
  sl.registerLazySingleton<NotificationInboxRepository>(
    () => NotificationInboxRepositoryImpl(localDataSource: sl(), remoteDataSource: sl(), supabase: sl()),
  );
  sl.registerLazySingleton<ProfileRemoteDataSource>(
    () => ProfileRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<ProfileLocalDataSource>(
    () => ProfileLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<SharedPresenceManager>(
    () => SharedPresenceManager(supabase: sl(), remoteDataSource: sl()),
  );
  sl.registerLazySingleton<ProfileRepository>(
    () => ProfileRepositoryImpl(remoteDataSource: sl(), localDataSource: sl(), supabase: sl(), presenceManager: sl()),
  );
  sl.registerLazySingleton<ProfileBulkWarmupService>(
    () => ProfileBulkWarmupService(remoteDataSource: sl(), localDataSource: sl(), supabase: sl(), presenceManager: sl()),
  );
  sl.registerLazySingleton<GroupProfileBulkWarmupService>(
    () => GroupProfileBulkWarmupService(sl()),
  );
  sl.registerLazySingleton<FriendRepository>(
    () => FriendRepositoryImpl(
      localDataSource: sl(),
      supabase: sl(),
      chatListRepository: sl(),
      getOrCreateDirectChatUseCase: sl(),
      chatRepository: sl(),
    ),
  );
  sl.registerLazySingleton<UserSearchRemoteDataSource>(
    () => UserSearchRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<UserSearchLocalDataSource>(
    () => UserSearchLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<UserSearchRepository>(
    () => UserSearchRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      supabase: sl(),
      friendRepository: sl(),
    ),
  );
  sl.registerLazySingleton<AdminRemoteDataSource>(
    () => AdminRemoteDataSourceImpl(client: sl()),
  );
  sl.registerLazySingleton<AdminLocalDataSource>(
    () => AdminLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<AdminRepository>(
    () => AdminRepositoryImpl(remoteDataSource: sl(), localDataSource: sl(), supabase: sl()),
  );

  sl.registerLazySingleton<AdminAuthorization>(() => const LocalAdminAuthorization());
  sl.registerLazySingleton<BanAuthorization>(() => LocalBanAuthorization(adminAuthorization: sl()));
  sl.registerLazySingleton<FriendActionAuthorization>(() => const LocalFriendActionAuthorization());
  sl.registerLazySingleton<FriendSecurityGateway>(
    () => LocalFriendSecurityGateway(friendRepository: sl(), friendActionAuthorization: sl()),
  );
  sl.registerLazySingleton<AdminSecurityGateway>(
    () => LocalAdminSecurityGateway(adminRepository: sl(), banAuthorization: sl(), adminAuthorization: sl()),
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
      localDataSource: sl(),
      mediaRepository: sl(),
      customAlertRepository: sl(),
      supabase: sl(),
    ),
  );

  sl.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSourceImpl(supabaseClient: sl()));
  sl.registerLazySingleton<ChatRemoteDataSource>(() => ChatRemoteDataSourceImpl(client: sl()));
  sl.registerLazySingleton<ChatLocalDataSource>(() => ChatLocalDataSourceImpl());
  sl.registerLazySingleton<MessageInboxApplicator>(() => MessageInboxApplicator(sl()));
  sl.registerLazySingleton<FriendLocalDataSource>(() => FriendLocalDataSourceImpl());
  sl.registerLazySingleton<ChatListLocalDataSource>(() => ChatListLocalDataSourceImpl());
  sl.registerLazySingleton<ChatListRemoteDataSource>(() => ChatListRemoteDataSourceImpl(client: sl()));
  sl.registerLazySingleton<AlertAudioMetadataLocalDataSource>(() => AlertAudioMetadataLocalDataSourceImpl());
  sl.registerLazySingleton<AlertSoundLocalDataSource>(() => AlertSoundLocalDataSourceImpl());
  sl.registerLazySingleton<AlertSoundRemoteDataSource>(() => AlertSoundRemoteDataSourceImpl(supabase: sl()));
  sl.registerLazySingleton<NotificationRemoteDataSource>(() => NotificationRemoteDataSourceImpl(client: sl()));
  sl.registerLazySingleton<NotificationLocalDataSource>(() => NotificationLocalDataSourceImpl());

  sl.registerLazySingleton<AudioCacheManager>(() => AudioCacheManager.instance);
  sl.registerLazySingleton<AudioDownloadManager>(() => AudioDownloadManager(client: sl()));
  sl.registerLazySingleton<AudioValidationService>(() => const AudioValidationService());

  sl.registerLazySingleton<FirebaseFirestore>(() => FirebaseFirestore.instance);
  sl.registerLazySingleton<SupabaseClient>(() => Supabase.instance.client);

  sl.registerLazySingleton(() => ModerationGuard(sl()));
  sl.registerLazySingleton<http.Client>(() => http.Client());
  sl.registerLazySingleton<NotificationService>(() => NotificationService.instance);

  sl.registerLazySingleton<VoiceRecordingService>(() => VoiceRecordingServiceImpl(VoiceRecorderService.instance));
  sl.registerFactory<VoicePlayerService>(() => VoicePlayerService());
  sl.registerFactory<VoicePlaybackController>(() => VoicePlaybackControllerImpl(VoicePlayerService()));

  sl.registerLazySingleton<VoiceDraftStore>(() => VoiceDraftStore.instance);
  sl.registerLazySingleton<VoiceRecordingCoordinator>(
    () => VoiceRecordingCoordinator(sl<VoiceRecordingService>(), sl<VoiceDraftStore>()),
  );

  // --- Call module (Milestone 2: Data Layer) -------------------------------
  // Datasources first, then repositories that depend on them, matching the
  // existing convention elsewhere in this file (get_it lazy singletons
  // don't require dependency-before-dependent ordering, but this keeps the
  // block readable in the same top-down style as the Chat/Friend/Profile
  // blocks above).
  sl.registerLazySingleton<CallRemoteDataSource>(
    () => CallRemoteDataSourceImpl(supabase: sl(), client: sl()),
  );
  sl.registerLazySingleton<CallRealtimeDataSource>(
    () => CallRealtimeDataSourceImpl(supabase: sl()),
  );
  sl.registerLazySingleton<AgoraDataSource>(() => AgoraDataSourceImpl());
  sl.registerLazySingleton<CallRepository>(
    () => CallRepositoryImpl(
      remoteDataSource: sl(),
      realtimeDataSource: sl(),
      supabase: sl(),
      pushNotificationSender: sl(),
    ),
  );
  sl.registerLazySingleton<AgoraRepository>(() => AgoraRepositoryImpl(dataSource: sl()));

  // Foundation Layer usecases (previously registered but not wired in,
  // per the prior milestone's explicit note) are wired in now that their
  // CallRepository/AgoraRepository dependencies actually resolve.
  registerCallFoundationUsecases(sl);

  // --- Call module (Milestone 3: Presentation Layer) ------------------
  // CallCubit / IncomingCallListenerCubit, registered last since both
  // depend on the usecases wired in immediately above.
  registerCallPresentation(sl);
}
