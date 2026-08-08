import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/agora_credentials_entity.dart';
import '../repositories/agora_repository.dart';

/// Joins the Agora channel using freshly fetched [credentials]
/// (Phase 1 §9/§10).
class JoinChannelUseCase {
  final AgoraRepository repository;
  const JoinChannelUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required AgoraCredentialsEntity credentials,
    required bool videoEnabled,
  }) {
    return repository.joinChannel(credentials, videoEnabled: videoEnabled);
  }
}
