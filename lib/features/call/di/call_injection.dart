import 'package:get_it/get_it.dart';

import '../domain/usecases/accept_call_usecase.dart';
import '../domain/usecases/cancel_call_usecase.dart';
import '../domain/usecases/decline_call_usecase.dart';
import '../domain/usecases/end_call_usecase.dart';
import '../domain/usecases/fetch_agora_token_usecase.dart';
import '../domain/usecases/get_call_history_usecase.dart';
import '../domain/usecases/initiate_call_usecase.dart';
import '../domain/usecases/join_channel_usecase.dart';
import '../domain/usecases/leave_channel_usecase.dart';
import '../domain/usecases/listen_call_status_usecase.dart';
import '../domain/usecases/listen_incoming_call_usecase.dart';
import '../domain/usecases/mark_call_busy_usecase.dart';
import '../domain/usecases/mark_call_missed_usecase.dart';
import '../domain/usecases/reconcile_stale_calls_usecase.dart';
import '../domain/usecases/refresh_agora_token_usecase.dart';
import '../domain/usecases/switch_camera_usecase.dart';
import '../domain/usecases/toggle_camera_usecase.dart';
import '../domain/usecases/toggle_mute_usecase.dart';
import '../domain/usecases/toggle_speaker_usecase.dart';

/// Registers the call module's domain-layer usecases with [sl].
///
/// FOUNDATION LAYER SCOPE ONLY:
/// - Registers usecases against the `CallRepository`/`AgoraRepository`
///   *abstractions* (`sl<CallRepository>()`, `sl<AgoraRepository>()`) only.
/// - Does NOT register `CallRepositoryImpl`/`AgoraRepositoryImpl`, any
///   datasource implementation, or the `SupabaseClient`/Agora engine those
///   would depend on — none of that exists yet by design (no Supabase
///   migration, no Edge Function, no Agora SDK in this milestone).
/// - Is NOT YET called from `core/di/injection_container.dart`'s `init()`.
///   Wiring this in is deferred to the milestone that adds the concrete
///   repository implementations.
///
/// This is safe to leave unwired: `get_it`'s `registerLazySingleton`
/// only evaluates its factory callback (and therefore only resolves
/// `sl<CallRepository>()`/`sl<AgoraRepository>()`) the first time something
/// asks for that usecase. Since nothing in the app calls into this module
/// yet (no UI, no signaling wired up), nothing will trigger that
/// resolution — so this file can exist, and even be called, without
/// breaking any currently-registered dependency in
/// `injection_container.dart`. It is being kept uncalled for now purely to
/// keep this milestone's diff to net-new files only, per the "do not
/// modify unrelated modules" instruction for this phase.
void registerCallFoundationUsecases(GetIt sl) {
  sl.registerLazySingleton(() => InitiateCallUseCase(callRepository: sl(), friendRepository: sl()));
  sl.registerLazySingleton(() => AcceptCallUseCase(sl()));
  sl.registerLazySingleton(() => DeclineCallUseCase(sl()));
  sl.registerLazySingleton(() => CancelCallUseCase(sl()));
  sl.registerLazySingleton(() => EndCallUseCase(sl()));
  sl.registerLazySingleton(() => MarkCallMissedUseCase(sl()));
  sl.registerLazySingleton(() => MarkCallBusyUseCase(sl()));
  sl.registerLazySingleton(() => FetchAgoraTokenUseCase(sl()));
  sl.registerLazySingleton(() => RefreshAgoraTokenUseCase(sl()));
  sl.registerLazySingleton(() => JoinChannelUseCase(sl()));
  sl.registerLazySingleton(() => LeaveChannelUseCase(sl()));
  sl.registerLazySingleton(() => ToggleMuteUseCase(sl()));
  sl.registerLazySingleton(() => ToggleCameraUseCase(sl()));
  sl.registerLazySingleton(() => SwitchCameraUseCase(sl()));
  sl.registerLazySingleton(() => ToggleSpeakerUseCase(sl()));
  sl.registerLazySingleton(() => ListenIncomingCallUseCase(sl()));
  sl.registerLazySingleton(() => ListenCallStatusUseCase(sl()));
  sl.registerLazySingleton(() => GetCallHistoryUseCase(sl()));
  sl.registerLazySingleton(
    () => ReconcileStaleCallsUseCase(repository: sl(), markCallMissedUseCase: sl(), endCallUseCase: sl()),
  );
}
