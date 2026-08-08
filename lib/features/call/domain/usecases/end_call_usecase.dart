import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../repositories/call_repository.dart';

/// Either participant ends a 'connected' call (Phase 1 §7).
class EndCallUseCase {
  final CallRepository repository;
  const EndCallUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String callId,
    required String endReason,
  }) {
    return repository.endCall(callId: callId, endReason: endReason);
  }
}
