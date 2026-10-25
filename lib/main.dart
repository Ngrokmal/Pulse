import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';

import 'core/di/injection_container.dart' as di;
import 'core/network/offline_queue.dart';
import 'core/supabase/supabase_init.dart';
import 'core/sync/group_delta_sync_coordinator.dart';
import 'core/navigation/app_navigator_key.dart';
import 'core/services/call_notification_router.dart';
import 'core/services/device_id_service.dart';
import 'core/services/fcm_message_handler.dart';
import 'core/services/friend_profile_cache_service.dart';
import 'core/services/local_db_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/chat/data/services/voice_recording_coordinator.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/cubit/auth_ui_cubit.dart';
import 'features/custom_alert/data/repositories/friend_alert_sound_repository_impl.dart';
import 'features/custom_alert/domain/repositories/friend_alert_sound_repository.dart';
import 'core/services/fcm_token_sync_service.dart';
import 'core/utils/fcm_sync_diagnostics.dart';
import 'features/auth/presentation/pages/auth_screen.dart';
import 'features/home/presentation/pages/home_screen.dart';
import 'features/chat/data/repositories/group_repository_impl.dart';
import 'features/chat/domain/repositories/group_repository.dart';
import 'features/notifications/data/repositories/notification_inbox_repository_impl.dart';
import 'features/notifications/domain/repositories/notification_inbox_repository.dart';
import 'features/notifications/domain/usecases/initialize_notifications_usecase.dart';
import 'features/notifications/domain/usecases/request_notification_permission_usecase.dart';
import 'features/profile/domain/usecases/set_online_status_usecase.dart';
import 'core/services/presence_activity_pinger.dart';
import 'core/constants/presence_constants.dart';
import 'features/call/presentation/cubit/incoming_call_listener_cubit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDbService.init();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await SupabaseInit.init();
  await di.init();
  (di.sl<NotificationInboxRepository>() as NotificationInboxRepositoryImpl).registerOfflineQueueHandlers();
  (di.sl<FriendAlertSoundRepository>() as FriendAlertSoundRepositoryImpl).registerOfflineQueueHandlers();
  (di.sl<GroupRepository>() as GroupRepositoryImpl).registerOfflineQueueHandlers();
  await OfflineQueueManager.instance.hydrate();
  await FriendProfileCacheService.instance.warmUp();

  await di.sl<VoiceRecordingCoordinator>().restoreFromDisk(SupabaseInit.client.auth.currentUser?.id);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await di.sl<InitializeNotificationsUseCase>().call();
  await di.sl<RequestNotificationPermissionUseCase>().call();

  FcmMessageHandler.instance.wire();
  await FcmMessageHandler.instance.handleTerminatedLaunch();

  // MILESTONE 7 (Incoming Call Routing & Notification Integration): same
  // two call sites as FcmMessageHandler immediately above, wired
  // separately since this is a distinct concern (call taps, not chat
  // taps) with its own payload shape — see CallNotificationRouter.
  CallNotificationRouter.instance.wire();
  await CallNotificationRouter.instance.handleTerminatedLaunch();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final SetOnlineStatusUseCase _setOnlineStatusUseCase = di.sl<SetOnlineStatusUseCase>();
  final PresenceActivityPinger _presenceActivityPinger = di.sl<PresenceActivityPinger>();
  StreamSubscription<AuthState>? _authSubscription;
  DateTime? _lastPresenceAt;
  bool? _lastPresenceOnline;

  String? _deviceId;

  String? _lastKnownUid;

  Timer? _heartbeatTimer;
  static const Duration _kHeartbeatInterval = PresenceConstants.heartbeatInterval;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initDeviceIdAndPresence());
    _authSubscription = SupabaseInit.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      FcmSyncLog.step(
        '_MyAppState.authSubscription',
        'onAuthStateChange event=${data.event} userId=${user?.id} '
        '(this is a SEPARATE subscription from AuthGate\'s StreamBuilder below — both listen to the same stream, '
        'so this line firing proves the underlying Supabase auth event itself fired for this account; if AuthGate\'s '
        'own "syncFor ENTER" log line is missing right after this one for the same userId, the break is in '
        'AuthGate/StreamBuilder specifically, not in the auth event itself)',
      );
      if (user != null) {
        _lastKnownUid = user.id;
        _updatePresence(true);
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        final signedOutUid = _lastKnownUid;
        final deviceId = _deviceId;
        if (signedOutUid != null && deviceId != null) {
          unawaited(_setOnlineStatusUseCase(uid: signedOutUid, isOnline: false, deviceId: deviceId));
        }
        _lastKnownUid = null;
        _lastPresenceOnline = null;
        _lastPresenceAt = null;
      }
      di.sl<VoiceRecordingCoordinator>().discardIfUserMismatch(user?.id);
    });
  }

  Future<void> _initDeviceIdAndPresence() async {
    _deviceId = await DeviceIdService.instance.getOrCreateDeviceId();
    _updatePresence(true);
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (SupabaseInit.client.auth.currentUser == null) return;
    _sendHeartbeat();
    _heartbeatTimer = Timer.periodic(_kHeartbeatInterval, (_) => _sendHeartbeat());
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeat() {
    _presenceActivityPinger.ping();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _updatePresence(true);
        _startHeartbeat();
        GroupDeltaSyncCoordinator.instance.notifyAppResumed();
        // MILESTONE 6 (Production Call Lifecycle): finalizes any call left
        // 'ringing'/'accepted' from before the app was backgrounded — see
        // IncomingCallListenerCubit.reconcileOnResume /
        // ReconcileStaleCallsUseCase. No-op if the user hasn't signed in
        // yet (nothing has called .start() to seed a userId).
        di.sl<IncomingCallListenerCubit>().reconcileOnResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _updatePresence(false);
        _stopHeartbeat();
        di.sl<VoiceRecordingCoordinator>().autoPauseIfInterrupted();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        di.sl<VoiceRecordingCoordinator>().autoPauseIfInterrupted();
        break;
    }
  }

  void _updatePresence(bool isOnline) {
    final uid = SupabaseInit.client.auth.currentUser?.id;
    final deviceId = _deviceId;
    if (uid == null || deviceId == null) return;

    final now = DateTime.now();
    if (_lastPresenceOnline == isOnline &&
        _lastPresenceAt != null &&
        now.difference(_lastPresenceAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastPresenceAt = now;
    _lastPresenceOnline = isOnline;

    _setOnlineStatusUseCase(uid: uid, isOnline: isOnline, deviceId: deviceId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _stopHeartbeat();
    _updatePresence(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(create: (_) => di.sl<AuthCubit>()),
        BlocProvider<AuthUiCubit>(create: (_) => di.sl<AuthUiCubit>()),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.instance.themeMode,
        builder: (context, mode, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: appNavigatorKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = SupabaseInit.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, snapshot) {
        FcmSyncLog.step(
          'AuthGate',
          'StreamBuilder rebuild: connectionState=${snapshot.connectionState} event=${snapshot.data?.event} '
          'userId=${snapshot.data?.session?.user.id} hasError=${snapshot.hasError}'
          '${snapshot.hasError ? ' error=${snapshot.error}' : ''}',
        );
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data?.session?.user;
        if (user != null) {
          FcmSyncLog.step('AuthGate', 'Calling FcmTokenSyncService.syncFor(uid=${user.id}) — DI instance hash: '
              '${di.sl<FcmTokenSyncService>().hashCode}');
          di.sl<FcmTokenSyncService>().syncFor(user.id);
          return HomeScreen(currentUserId: user.id);
        }
        FcmSyncLog.step('AuthGate', 'No session — calling FcmTokenSyncService.resetForLogout()');
        di.sl<FcmTokenSyncService>().resetForLogout();
        return AuthScreen();
      },
    );
  }
}
