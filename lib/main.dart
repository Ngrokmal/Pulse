import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'firebase_options.dart';

import 'core/di/injection_container.dart' as di;
import 'core/navigation/app_navigator_key.dart';
import 'core/services/fcm_message_handler.dart';
import 'core/services/friend_profile_cache_service.dart';
import 'core/services/local_db_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/chat/data/services/voice_recording_coordinator.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/cubit/auth_ui_cubit.dart';
import 'core/services/fcm_token_sync_service.dart';
import 'features/auth/presentation/pages/auth_screen.dart';
import 'features/home/presentation/pages/home_screen.dart';
import 'features/notifications/domain/usecases/initialize_notifications_usecase.dart';
import 'features/notifications/domain/usecases/request_notification_permission_usecase.dart';
import 'features/profile/domain/usecases/set_online_status_usecase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDbService.init();
  // lib/firebase_options.dart currently holds placeholder values (see the
  // TODO(manual) notes in that file). Run `flutterfire configure` once the
  // real google-services.json is in place to replace them with real config.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await di.init();
  // Task 2 (Friend Profile Local Cache): load the SharedPreferences instance
  // once up front so ChatAppBar's synchronous getCachedSync() has data
  // ready on the very first frame instead of returning null until the
  // first async read completes.
  await FriendProfileCacheService.instance.warmUp();

  // Voice Message audit (Bug 3): if the process was previously killed while
  // a voice message was mid-recording, recover whatever partial audio
  // survived on disk as a draft instead of silently losing it. Local-only —
  // no Firestore/network involved. Scoped to whoever is currently signed in
  // (if the sidecar belongs to a different/no account, it's discarded
  // instead of restored — see VoiceDraftStore.restoreFromDisk).
  await di.sl<VoiceRecordingCoordinator>().restoreFromDisk(FirebaseAuth.instance.currentUser?.uid);

  // Milestone 7.2 (Notification Handling): ব্যাকগ্রাউন্ড আইসোলেট হ্যান্ডলার
  // অবশ্যই `runApp()`-এর আগে রেজিস্টার করতে হয় (FCM-এর নিয়ম)।
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 7.1-এ তৈরি হওয়া UseCase দুটো (Android channel init + runtime permission)
  // আগে কোথাও কল হতো না — এখন বাস্তবে ওয়্যার করা হলো, যাতে ৭.২-এর
  // foreground/background নোটিফিকেশন প্রদর্শন আসলে কাজ করতে পারে।
  await di.sl<InitializeNotificationsUseCase>().call();
  await di.sl<RequestNotificationPermissionUseCase>().call();

  // Foreground/background-tap/local-notification-tap লিসেনার ওয়্যারিং +
  // terminated-state লঞ্চ চেক (দেখুন lib/core/services/fcm_message_handler.dart)।
  FcmMessageHandler.instance.wire();
  await FcmMessageHandler.instance.handleTerminatedLaunch();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final SetOnlineStatusUseCase _setOnlineStatusUseCase = di.sl<SetOnlineStatusUseCase>();
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updatePresence(true);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _updatePresence(true);
      // Voice Message audit (fix: draft visible across chats/accounts):
      // any account switch (login, logout, or switching to a different
      // account) must never let a previous account's paused voice
      // recording surface for the new session — discard it outright
      // rather than merely hiding it, cancelling a still-live recording
      // if there is one.
      di.sl<VoiceRecordingCoordinator>().discardIfUserMismatch(user?.uid);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _updatePresence(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _updatePresence(false);
        // Voice Message audit (Bug 3): app backgrounded / Home pressed /
        // screen locked / incoming call / notification interruption — auto
        // -pause instead of losing the recording. No-op if nothing is
        // actively recording. Reuses the same existing app-wide lifecycle
        // observer already here for presence; no new observer added.
        di.sl<VoiceRecordingCoordinator>().autoPauseIfInterrupted();
        break;
    }
  }

  void _updatePresence(bool isOnline) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _setOnlineStatusUseCase(uid: uid, isOnline: isOnline);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
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

/// Phase 8.5G (Real Firebase Authentication Migration).
///
/// Single entry point that decides Auth vs Home using
/// `FirebaseAuth.instance.authStateChanges()` — the real, persisted
/// Firebase session — instead of unconditionally showing AuthScreen.
/// Before this migration `home:` was hardcoded to AuthScreen, so an
/// already-signed-in user was always dropped back on the login form
/// on every cold start. AuthCubit is deliberately NOT used for this
/// decision: it's a `registerFactory` (a fresh, AuthInitial instance
/// every build) and only ever changes state in response to an
/// explicit login()/register() call made during this session — it
/// cannot see a session Firebase already restored from disk.
/// `FirebaseAuth.currentUser` / `authStateChanges()` remain the only
/// source of truth for "is someone logged in".
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user != null) {
          // Missing-link fix (notification delivery audit): the FCM sender
          // Cloud Function reads users/{uid}.fcmToken — this call is what
          // actually writes it. Fire-and-forget; navigation never waits on it.
          di.sl<FcmTokenSyncService>().syncFor(user.uid);
          return HomeScreen(currentUserId: user.uid);
        }
        return AuthScreen();
      },
    );
  }
}
