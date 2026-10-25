import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/agora_credentials_entity.dart';
import '../repositories/call_repository.dart';

/// Fetches a fresh Agora token immediately before joining a channel
/// (Phase 1 §9 — never reuse a token obtained earlier in the flow).
class FetchAgoraTokenUseCase {
  final CallRepository repository;
  const FetchAgoraTokenUseCase(this.repository);

  Future<Either<Failure, AgoraCredentialsEntity>> call({
    required String callId,
    required String channelName,
    required int uid,
  }) {
    return repository.getAgoraToken(callId: callId, channelName: channelName, uid: uid);
  }
}
