import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/agora_credentials_entity.dart';
import '../entities/agora_engine_event.dart';

/// Contract for the Agora RTC media layer (Phase 1 §4.2/§6). Implemented by
/// `AgoraRepositoryImpl` (data layer — NOT part of this milestone; that is
/// the only implementation permitted to eventually depend on the
/// `agora_rtc_engine` package, and only indirectly via `AgoraDataSource`).
///
/// No Agora SDK types appear in this contract — everything is expressed in
/// domain entities/events, per Phase 1 §3.1 ("no business logic leaks past
/// the datasource boundary").
abstract class AgoraRepository {
  /// Lazily creates the underlying RTC engine (Phase 1 §6 — not kept warm
  /// across calls).
  Future<Either<Failure, void>> initialize(String appId);

  /// Joins the channel described by [credentials]. [videoEnabled]
  /// determines whether local video is enabled from the start (audio-only
  /// vs. video call).
  Future<Either<Failure, void>> joinChannel(
    AgoraCredentialsEntity credentials, {
    required bool videoEnabled,
  });

  /// Leaves the current channel. Always paired with [dispose] by the
  /// caller (Phase 1 §6 — try/finally so a mid-call crash still tears down
  /// the engine).
  Future<Either<Failure, void>> leaveChannel();

  Future<Either<Failure, void>> toggleMute(bool muted);

  Future<Either<Failure, void>> toggleCamera(bool enabled);

  Future<Either<Failure, void>> switchCamera();

  Future<Either<Failure, void>> toggleSpeaker(bool enabled);

  /// Domain-level stream of engine events (Phase 1 §3.4) — this is how a
  /// future `CallCubit` derives "Connected" (on [AgoraUserJoined]) rather
  /// than trusting a Supabase-asserted status.
  Stream<AgoraEngineEvent> get engineEvents;

  /// MILESTONE 5: applies a freshly-fetched token to the live engine,
  /// in response to [AgoraTokenExpiringSoon] — see
  /// `RefreshAgoraTokenUseCase` for how the new token is obtained.
  Future<Either<Failure, void>> renewToken(String token);

  /// MILESTONE 5: type-erased handle to the live engine instance, for
  /// presentation-layer video-preview widgets only (see
  /// [AgoraDataSource.engineHandle] for why this stays `Object?` rather
  /// than importing the SDK type here).
  Object? get engineHandle;

  /// Tears down the native engine instance entirely (Phase 1 §6).
  Future<void> dispose();
}
