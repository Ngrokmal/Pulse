import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/agora_credentials_entity.dart';
import '../../domain/entities/agora_engine_event.dart';
import '../../domain/failures/call_failures.dart';
import '../../domain/repositories/agora_repository.dart';
import '../datasources/agora_datasource.dart';

/// Concrete [AgoraRepository]. Thin `Either<Failure, T>` wrapper around
/// [AgoraDataSource] — all Agora SDK specifics stay inside the datasource
/// (Phase 1 §6); this class's only job is catching whatever the datasource
/// throws and mapping it to [AgoraEngineFailure], matching the
/// try/catch-based FailureMapper style used throughout the project's
/// existing repositories.
class AgoraRepositoryImpl implements AgoraRepository {
  final AgoraDataSource dataSource;

  AgoraRepositoryImpl({required this.dataSource});

  @override
  Future<Either<Failure, void>> initialize(String appId) async {
    try {
      await dataSource.initializeEngine(appId);
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> joinChannel(
    AgoraCredentialsEntity credentials, {
    required bool videoEnabled,
  }) async {
    try {
      await dataSource.joinChannel(
        token: credentials.token,
        channelName: credentials.channelName,
        uid: credentials.uid,
        videoEnabled: videoEnabled,
      );
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> leaveChannel() async {
    try {
      await dataSource.leaveChannel();
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> toggleMute(bool muted) async {
    try {
      await dataSource.muteLocalAudio(muted);
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> toggleCamera(bool enabled) async {
    try {
      await dataSource.enableLocalVideo(enabled);
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> switchCamera() async {
    try {
      await dataSource.switchCamera();
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> toggleSpeaker(bool enabled) async {
    try {
      await dataSource.setEnableSpeakerphone(enabled);
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Stream<AgoraEngineEvent> get engineEvents => dataSource.events;

  @override
  Future<Either<Failure, void>> renewToken(String token) async {
    try {
      await dataSource.renewToken(token);
      return const Right(null);
    } catch (e) {
      return Left(AgoraEngineFailure(e.toString()));
    }
  }

  @override
  Object? get engineHandle => dataSource.engineHandle;

  @override
  Future<void> dispose() => dataSource.destroyEngine();
}
