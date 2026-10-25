import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/agora_repository.dart';

/// Leaves the current Agora channel. Callers are expected to also invoke
/// engine teardown (Phase 1 §6) — that's `AgoraRepository.dispose()`,
/// deliberately kept separate from this usecase so leave/dispose can be
/// sequenced explicitly (e.g. try/finally) by whoever owns the call
/// lifecycle.
class LeaveChannelUseCase {
  final AgoraRepository repository;
  const LeaveChannelUseCase(this.repository);

  Future<Either<Failure, void>> call() {
    return repository.leaveChannel();
  }
}
