import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/agora_credentials_entity.dart';
import '../repositories/call_repository.dart';

/// Mid-call proactive refresh, triggered by [AgoraTokenExpiringSoon]
/// (Phase 1 §9) — transparent to the user, no re-join.
class RefreshAgoraTokenUseCase {
  final CallRepository repository;
  const RefreshAgoraTokenUseCase(this.repository);

  Future<Either<Failure, AgoraCredentialsEntity>> call({
    required String callId,
    required String channelName,
    required int uid,
  }) {
    return repository.refreshAgoraToken(callId: callId, channelName: channelName, uid: uid);
  }
}
