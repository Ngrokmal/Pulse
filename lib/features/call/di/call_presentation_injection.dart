import 'package:get_it/get_it.dart';

import '../../profile/domain/repositories/profile_repository.dart';
import '../domain/repositories/agora_repository.dart';
import '../presentation/cubit/call_cubit.dart';
import '../presentation/cubit/incoming_call_listener_cubit.dart';

/// Registers the call module's Presentation Layer (Milestone 3).
///
/// - `CallCubit` is `registerFactory` — a new instance per call attempt,
///   matching `AuthCubit`/`ChatBloc`'s per-screen-lifetime convention
///   (never reused across two different calls).
/// - `IncomingCallListenerCubit` is `registerLazySingleton` — one
///   app-wide instance, started once from `HomeScreen.initState` via
///   `.start(uid)`, mirroring `NotificationBadgeCubit`'s exact pattern.
///
/// Depends on the call module's usecases/repositories (registered in
/// `call_injection.dart` + the Call module block of
/// `injection_container.dart`, both from Milestone 2) and on
/// `ProfileRepository` (already registered for the Profile feature) for
/// resolving a call peer's display name/avatar — no new domain-layer
/// registration is added here.
void registerCallPresentation(GetIt sl) {
  sl.registerFactory(
    () => CallCubit(
      initiateCallUseCase: sl(),
      acceptCallUseCase: sl(),
      declineCallUseCase: sl(),
      cancelCallUseCase: sl(),
      endCallUseCase: sl(),
      markCallMissedUseCase: sl(),
      fetchAgoraTokenUseCase: sl(),
      refreshAgoraTokenUseCase: sl(),
      joinChannelUseCase: sl(),
      leaveChannelUseCase: sl(),
      toggleMuteUseCase: sl(),
      toggleCameraUseCase: sl(),
      switchCameraUseCase: sl(),
      toggleSpeakerUseCase: sl(),
      listenCallStatusUseCase: sl(),
      agoraRepository: sl<AgoraRepository>(),
      profileRepository: sl<ProfileRepository>(),
    ),
  );

  sl.registerLazySingleton(
    () => IncomingCallListenerCubit(
      listenIncomingCallUseCase: sl(),
      markCallBusyUseCase: sl(),
      reconcileStaleCallsUseCase: sl(),
    ),
  );
}
